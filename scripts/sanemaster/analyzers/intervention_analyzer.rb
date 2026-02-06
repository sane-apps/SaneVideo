# frozen_string_literal: true

module SaneMasterModules
  module Analyzers
    # Parses conversation history for user corrections and frustrations
    class InterventionAnalyzer
      HISTORY_PATH = File.expand_path('~/.claude/history.jsonl')
      OUTPUT_PATH = File.expand_path('~/.claude/collab/interventions.jsonl')

      # Detection patterns with weights
      PATTERNS = {
        high: {
          direct_correction: /\b(no|wrong|that's not|that is not|i said|i already|you're not)\b/i,
          frustration: /\b(idiot|check the sop|wtf|what the|seriously|come on|ugh)\b/i,
          explicit_error: /\b(that's wrong|you made|mistake|error|incorrect|not right)\b/i,
          repeated_instruction: /\b(again|i told you|i already said|as i mentioned)\b/i
        },
        medium: {
          redirect: /\b(actually|instead|not that|rather|let me clarify)\b/i,
          negative_sentiment: /\b(don't|stop|why did you|shouldn't|can't believe)\b/i,
          correction_marker: /\b(but|however|no,|nope)\s/i
        },
        low: {
          mild_redirect: /\b(hmm|well|maybe|perhaps not)\b/i,
          clarification: /\b(what i meant|to clarify|let me explain)\b/i
        }
      }.freeze

      # Context extraction patterns - what was the correction about?
      CONTEXT_PATTERNS = {
        screenshot: /\b(screenshot|ss|screen\s*shot|capture)\b/i,
        sop: /\b(sop|rules|development\.md|claude\.md)\b/i,
        memory: /\b(memory|remember|forgot|mcp)\b/i,
        build: /\b(build|compile|xcode|verify)\b/i,
        test: /\b(test|spec|regression)\b/i,
        path: /\b(path|location|directory|folder|file)\b/i,
        api: /\b(api|sdk|framework|method|function)\b/i,
        version: /\b(version|wrong version|old version|binary)\b/i
      }.freeze

      def initialize
        @interventions = []
      end

      def analyze(options = {})
        return { error: 'History file not found' } unless File.exist?(HISTORY_PATH)

        days_back = options[:days] || 30
        cutoff = Time.now - (days_back * 24 * 60 * 60)

        parse_history(cutoff)
        save_results
        generate_summary
      end

      def recent_interventions(limit = 10)
        load_existing_interventions.last(limit)
      end

      def pattern_frequency
        interventions = load_existing_interventions
        freq = Hash.new(0)
        interventions.each { |i| freq[i['pattern']] += 1 }
        freq.sort_by { |_, v| -v }.to_h
      end

      def suggestions(threshold = 3)
        freq = pattern_frequency
        freq.select { |_, count| count >= threshold }.map do |pattern, count|
          {
            pattern: pattern,
            count: count,
            suggestion: generate_suggestion(pattern)
          }
        end
      end

      private

      def parse_history(cutoff)
        File.foreach(HISTORY_PATH) do |line|
          entry = parse_entry(line)
          next unless entry && entry[:timestamp] && entry[:timestamp] > cutoff
          next unless %w[human user].include?(entry[:role])

          analyze_message(entry)
        end
      end

      def parse_entry(line)
        data = JSON.parse(line)
        # Claude Code history format uses 'display' for content and 'timestamp' as milliseconds
        content = data['display']
        return nil if content.nil? || content.start_with?('/') # Skip slash commands

        {
          timestamp: parse_timestamp(data['timestamp']),
          role: 'user', # All entries in history.jsonl are user messages
          content: content,
          session: data['sessionId']
        }
      rescue JSON::ParserError
        nil
      end

      def parse_timestamp(ts)
        return nil unless ts

        if ts.is_a?(Numeric)
          Time.at(ts / 1000.0) # Milliseconds to seconds
        else
          Time.parse(ts)
        end
      rescue ArgumentError
        nil
      end

      def analyze_message(entry)
        content = entry[:content].to_s
        return if content.length < 3 # Skip very short messages

        weight, pattern_name = detect_intervention(content)
        return unless weight

        context = detect_context(content)

        @interventions << {
          timestamp: entry[:timestamp]&.iso8601,
          session: entry[:session],
          signal: weight.to_s,
          pattern: pattern_name,
          context: context,
          user_message: content[0, 200], # Truncate for storage
          suggested_rule: generate_rule_suggestion(pattern_name, context)
        }
      end

      def detect_intervention(content)
        PATTERNS.each do |weight, patterns|
          patterns.each do |name, regex|
            return [weight, name.to_s] if content.match?(regex)
          end
        end
        nil
      end

      def detect_context(content)
        CONTEXT_PATTERNS.each do |ctx, regex|
          return ctx.to_s if content.match?(regex)
        end
        'general'
      end

      def generate_rule_suggestion(pattern, context)
        case pattern
        when 'direct_correction', 'explicit_error'
          "Add verification step for #{context} before proceeding"
        when 'frustration'
          "Check SOP/memory for #{context} patterns before acting"
        when 'repeated_instruction'
          "Create hook to enforce #{context} checks automatically"
        end
      end

      def generate_suggestion(pattern)
        case pattern
        when 'direct_correction', 'explicit_error'
          'Add pre-tool verification hook'
        when 'frustration'
          'Strengthen SOP enforcement'
        when 'repeated_instruction'
          'Create automated reminder hook'
        when 'redirect'
          'Improve context gathering before action'
        else
          'Review and add specific guardrail'
        end
      end

      def save_results
        FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))

        # Append new interventions
        File.open(OUTPUT_PATH, 'a') do |f|
          @interventions.each do |intervention|
            f.puts(JSON.generate(intervention))
          end
        end
      end

      def load_existing_interventions
        return [] unless File.exist?(OUTPUT_PATH)

        File.readlines(OUTPUT_PATH).filter_map do |line|
          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end
      end

      def generate_summary
        all = load_existing_interventions
        recent = all.last(50)

        {
          total: all.count,
          by_weight: count_by_field(recent, 'signal'),
          by_pattern: count_by_field(recent, 'pattern'),
          by_context: count_by_field(recent, 'context'),
          suggestions: suggestions
        }
      end

      def count_by_field(items, field)
        counts = Hash.new(0)
        items.each { |i| counts[i[field]] += 1 }
        counts.sort_by { |_, v| -v }.to_h
      end
    end
  end
end
