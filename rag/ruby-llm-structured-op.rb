#!/usr/bin/env ruby
# frozen_string_literal: true

require "ruby_llm"
require "schematist"
require "opensearch-ruby"
require "json"

# Configure RubyLLM to use a local LLM running on port 8000
# (OpenAI-compatible endpoint, e.g. vLLM, LiteLLM, LocalAI, etc.)
RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("LOCAL_LLM_API_KEY", "omlx-jtaf2dagu4yondp4")
  config.openai_api_base = "http://localhost:8000/v1"
end

# OpenSearch client configuration (local cluster, no auth by default)
OPENSEARCH_HOST = ENV.fetch("OPENSEARCH_HOST", "http://localhost:9200")
OPENSEARCH_USER = ENV.fetch("OPENSEARCH_USER", "admin")
OPENSEARCH_PASS = ENV.fetch("OPENSEARCH_PASS", "Welcome@123456")
INDEX_NAME = "support-tickets"

opensearch = OpenSearch::Client.new(
  host: OPENSEARCH_HOST,
  user: OPENSEARCH_USER,
  password: OPENSEARCH_PASS,
  transport_options: { ssl: { verify: false } }
)

# Embedding model configuration
EMBEDDING_MODEL = "embeddinggemma-300m-bf16"

# Define the structured output schema for support ticket extraction
class SupportTicketSchema < Schematist::Schema
  string :client_name, required: false, description: "Name of the client organization"
  string :client_url, required: false, description: "Client's platform URL"
  string :environment, required: false, description: "Environment (e.g. Production, Staging, Development)"
  string :case_number, required: false, description: "Support case or ticket number"
  string :priority, required: false, description: "Priority level (e.g. Critical, High, Medium, Low)"
end

# Create the OpenSearch index with knn_vector mapping if it doesn't exist
def create_index_if_not_exists(client, index_name)
  unless client.indices.exists?(index: index_name)
    puts "Creating OpenSearch index: #{index_name}"
    index_body = {
      settings: {
        index: {
          knn: true,
          number_of_shards: 1,
          number_of_replicas: 0
        }
      },
      mappings: {
        properties: {
          filename: { type: "keyword" },
          raw_text: { type: "text" },
          client_name: { type: "keyword" },
          client_url: { type: "keyword" },
          environment: { type: "keyword" },
          case_number: { type: "keyword" },
          priority: { type: "keyword" },
          embedding: {
            type: "knn_vector",
            dimension: 768, # embeddinggemma-300m-bf16 produces 768-dim vectors
            method: {
              name: "hnsw",
              space_type: "cosinesimil",
              engine: "lucene"
            }
          }
        }
      }
    }
    client.indices.create(index: index_name, body: index_body)
    puts "Index '#{index_name}' created successfully."
  else
    puts "Index '#{index_name}' already exists."
  end
end

# Generate embedding for text using the local embeddinggemma-300m-bf16 model
def generate_embedding(text)
  embedding_result = RubyLLM.embed(
    text,
    model: EMBEDDING_MODEL,
    provider: :openai,
    assume_model_exists: true
  )
  embedding_result.vectors
end

# Directory containing ticket files
DATA_DIR = File.expand_path("data", __dir__)

# Collect all .txt ticket files
ticket_files = Dir.glob(File.join(DATA_DIR, "*.txt")).sort

if ticket_files.empty?
  puts "No ticket files found in #{DATA_DIR}"
  exit 1
end

puts "Found #{ticket_files.size} ticket(s) in #{DATA_DIR}"
puts "=" * 70

# Create the OpenSearch index
create_index_if_not_exists(opensearch, INDEX_NAME)

# Create a single chat session (reused across tickets for efficiency)
chat = RubyLLM.chat(
  model: "gemma-4-e4b-it-bf16",
  provider: :openai,
  assume_model_exists: true
)

results = []

ticket_files.each_with_index do |file_path, index|
  filename = File.basename(file_path)
  content = File.read(file_path)

  puts "\n[#{index + 1}/#{ticket_files.size}] Processing: #{filename}"
  puts "-" * 70

  prompt = <<~PROMPT
    Extract the following fields from the support ticket below. All fields are optional — only include them if clearly present in the text.

    Fields to extract:
    - client_name: The client organization name
    - client_url: The client's platform URL
    - environment: The environment (Production, Staging, etc.)
    - case_number: The case/ticket number
    - priority: The priority level if mentioned (Critical, High, Medium, Low)

    Support Ticket:
    #{content}
  PROMPT

  begin
    # Step 1: Extract structured fields using LLM
    response = chat.with_schema(SupportTicketSchema).ask(prompt)
    parsed = response.content

    # Step 2: Generate embedding for the raw ticket text
    puts "  Generating embedding..."
    embedding = generate_embedding(content)
    puts "  Embedding dimension: #{embedding.length}"

    # Step 3: Index the document into OpenSearch
    document = {
      filename: filename,
      raw_text: content,
      client_name: parsed["client_name"],
      client_url: parsed["client_url"],
      environment: parsed["environment"],
      case_number: parsed["case_number"],
      priority: parsed["priority"],
      embedding: embedding
    }

    doc_id = File.basename(filename, ".txt") # Use ticket ID as document ID
    opensearch.index(
      index: INDEX_NAME,
      body: document,
      id: doc_id,
      refresh: true
    )

    results << { file: filename, data: parsed, indexed: true }

    puts "  Client Name:  #{parsed['client_name'] || '(not found)'}"
    puts "  Client URL:   #{parsed['client_url'] || '(not found)'}"
    puts "  Environment:  #{parsed['environment'] || '(not found)'}"
    puts "  Case Number:  #{parsed['case_number'] || '(not found)'}"
    puts "  Priority:     #{parsed['priority'] || '(not found)'}"
    puts "  Indexed to OpenSearch as: #{doc_id}"
  rescue StandardError => e
    puts "  ERROR: #{e.message}"
    results << { file: filename, error: e.message }
  end
end

# Summary output
puts "\n"
puts "=" * 70
puts "SUMMARY: Processed #{results.size} ticket(s)"
puts "=" * 70

successful = results.reject { |r| r[:error] }
failed = results.select { |r| r[:error] }

puts "  Successful: #{successful.size}"
puts "  Failed:     #{failed.size}"
puts "  Indexed:    #{successful.count { |r| r[:indexed] }}"

if failed.any?
  puts "\n  Failed tickets:"
  failed.each { |r| puts "    - #{r[:file]}: #{r[:error]}" }
end
