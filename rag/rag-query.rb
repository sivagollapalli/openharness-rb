#!/usr/bin/env ruby
# frozen_string_literal: true

require "ruby_llm"
require "opensearch-ruby"
require "json"

# Configure RubyLLM to use a local LLM running on port 8000
RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("LOCAL_LLM_API_KEY", "omlx-jtaf2dagu4yondp4")
  config.openai_api_base = "http://localhost:8000/v1"
end

# OpenSearch client configuration
OPENSEARCH_HOST = ENV.fetch("OPENSEARCH_HOST", "http://localhost:9200")
OPENSEARCH_USER = ENV.fetch("OPENSEARCH_USER", "admin")
OPENSEARCH_PASS = ENV.fetch("OPENSEARCH_PASS", "Welcome@123456")
INDEX_NAME = "support-tickets"

# Models
EMBEDDING_MODEL = "embeddinggemma-300m-bf16"
CHAT_MODEL = "gemma-4-e4b-it-bf16"

# Number of relevant tickets to retrieve
TOP_K = 5

opensearch = OpenSearch::Client.new(
  host: OPENSEARCH_HOST,
  user: OPENSEARCH_USER,
  password: OPENSEARCH_PASS,
  transport_options: { ssl: { verify: false } }
)

# Generate embedding for the user query
def generate_query_embedding(text)
  embedding_result = RubyLLM.embed(
    text,
    model: EMBEDDING_MODEL,
    provider: :openai,
    assume_model_exists: true
  )
  embedding_result.vectors
end

# Hybrid search: combines kNN vector similarity + BM25 text match
def search_similar_tickets(client, query_text, query_embedding, top_k)
  search_body = {
    size: top_k,
    query: {
      hybrid: {
        queries: [
          # BM25 text search on raw_text and structured fields
          {
            bool: {
              should: [
                { match: { raw_text: { query: query_text, boost: 1.0 } } },
                { match: { client_name: { query: query_text, boost: 1.5 } } },
                { match: { case_number: { query: query_text, boost: 2.0 } } }
              ]
            }
          },
          # kNN vector similarity search
          {
            knn: {
              embedding: {
                vector: query_embedding,
                k: top_k
              }
            }
          }
        ]
      }
    },
    _source: {
      excludes: ["embedding"] # Don't return the large vector in results
    }
  }

  response = client.search(
    index: INDEX_NAME,
    body: search_body,
    search_pipeline: "nlp-search-pipeline"
  )
  response["hits"]["hits"]
rescue OpenSearch::Transport::Transport::Errors::BadRequest, OpenSearch::Transport::Transport::Errors::Forbidden, ArgumentError => e
    # Fallback: if hybrid query or search pipeline isn't available,
    # use a bool query combining knn and match as separate clauses
    puts "  Hybrid query not supported, falling back to combined bool query..."
    fallback_search(client, query_text, query_embedding, top_k)
end

# Fallback search combining kNN and BM25 using a bool query
def fallback_search(client, query_text, query_embedding, top_k)
  search_body = {
    size: top_k,
    query: {
      bool: {
        should: [
          # BM25 text match
          { match: { raw_text: { query: query_text, boost: 1.0 } } },
          { match: { client_name: { query: query_text, boost: 1.5 } } },
          { match: { case_number: { query: query_text, boost: 2.0 } } },
          # kNN vector similarity
          {
            knn: {
              embedding: {
                vector: query_embedding,
                k: top_k
              }
            }
          }
        ]
      }
    },
    _source: {
      excludes: ["embedding"]
    }
  }

  response = client.search(index: INDEX_NAME, body: search_body)
  response["hits"]["hits"]
end

# Format retrieved tickets as context for the LLM
def format_context(hits)
  hits.map.with_index(1) do |hit, idx|
    source = hit["_source"]
    score = hit["_score"]

    context = "--- Ticket #{idx} (relevance: #{score&.round(4)}) ---\n"
    context += "File: #{source['filename']}\n"
    context += "Client: #{source['client_name']}\n" if source["client_name"]
    context += "URL: #{source['client_url']}\n" if source["client_url"]
    context += "Environment: #{source['environment']}\n" if source["environment"]
    context += "Case Number: #{source['case_number']}\n" if source["case_number"]
    context += "Priority: #{source['priority']}\n" if source["priority"]
    context += "Content:\n#{source['raw_text']}\n"
    context
  end.join("\n")
end

# Build the RAG prompt with retrieved context
def build_rag_prompt(query, context)
  <<~PROMPT
    You are a helpful support engineer assistant. Answer the user's question based on the relevant support tickets provided below.

    If the answer can be found in the tickets, provide a detailed response citing the relevant ticket(s).
    If the tickets don't contain enough information to fully answer, say so and provide what you can based on available context.

    ## Relevant Support Tickets:
    #{context}

    ## User Question:
    #{query}

    ## Answer:
  PROMPT
end

# Main RAG pipeline
def rag_query(opensearch, chat, query)
  puts "\nQuery: #{query}"
  puts "=" * 70

  # Step 1: Generate embedding for the query
  puts "Generating query embedding..."
  query_embedding = generate_query_embedding(query)

  # Step 2: Retrieve similar tickets from OpenSearch (hybrid: BM25 + kNN)
  puts "Searching for relevant tickets (hybrid: BM25 + vector)..."
  hits = search_similar_tickets(opensearch, query, query_embedding, TOP_K)

  if hits.empty?
    puts "No relevant tickets found."
    return
  end

  puts "Found #{hits.size} relevant ticket(s):"
  hits.each_with_index do |hit, idx|
    source = hit["_source"]
    puts "  #{idx + 1}. #{source['filename']} (score: #{hit['_score']&.round(4)})"
  end

  # Step 3: Build context from retrieved tickets
  context = format_context(hits)

  # Step 4: Generate answer using LLM with retrieved context
  puts "\nGenerating answer...\n"
  puts "-" * 70

  prompt = build_rag_prompt(query, context)
  response = chat.ask(prompt)

  puts response.content
  puts "-" * 70
end

# Interactive REPL mode
def interactive_mode(opensearch)
  puts "=" * 70
  puts "  RAG Support Ticket Assistant"
  puts "  Model: #{CHAT_MODEL} | Embeddings: #{EMBEDDING_MODEL}"
  puts "  Index: #{INDEX_NAME} | Top-K: #{TOP_K}"
  puts "=" * 70
  puts "\nAsk questions about support tickets. Type 'quit' or 'exit' to stop.\n"

  chat = RubyLLM.chat(
    model: CHAT_MODEL,
    provider: :openai,
    assume_model_exists: true
  )

  loop do
    print "\n> "
    query = $stdin.gets&.strip

    break if query.nil? || query.empty? || %w[quit exit q].include?(query.downcase)

    begin
      rag_query(opensearch, chat, query)
    rescue StandardError => e
      puts "ERROR: #{e.message}"
      puts e.backtrace.first(3).join("\n") if ENV["DEBUG"]
    end
  end

  puts "\nGoodbye!"
end

# Entry point — support both interactive and single-query mode
if ARGV.empty?
  interactive_mode(opensearch)
else
  query = ARGV.join(" ")
  chat = RubyLLM.chat(
    model: CHAT_MODEL,
    provider: :openai,
    assume_model_exists: true
  )
  rag_query(opensearch, chat, query)
end
