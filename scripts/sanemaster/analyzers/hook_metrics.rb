# frozen_string_literal: true

module SaneMasterModules
  module Analyzers
    # Aggregates hook effectiveness metrics from audit log
    class HookMetrics
      AUDIT_LOG_PATH = File.expand_path('.claude/audit_log.jsonl', Dir.pwd)
      OUTPUT_PATH = File.expand_path('~/.claude/collab/hook_metrics.json')

      def initialize
        @entries = []
      end

      def analyze(options = {})
        return { error: 'Audit log not found', path: AUDIT_LOG_PATH } unless File.exist?(AUDIT_LOG_PATH)

        days_back = options[:days] || 7
        cutoff = Time.now - (days_back * 24 * 60 * 60)

        load_audit_log(cutoff)
        metrics = compute_metrics
        save_metrics(metrics)
        metrics
      end

      def current_session_metrics
        return {} unless File.exist?(AUDIT_LOG_PATH)

        # Get current session ID from most recent entry
        entries = load_all_entries
        return {} if entries.empty?

        current_session = entries.last['session']
        session_entries = entries.select { |e| e['session'] == current_session }

        compute_metrics_for(session_entries)
      end

      private

      def load_audit_log(cutoff)
        @entries = []
        File.foreach(AUDIT_LOG_PATH) do |line|
          entry = JSON.parse(line)
          timestamp = begin
            Time.parse(entry['timestamp'])
          rescue StandardError
            nil
          end
          next unless timestamp && timestamp > cutoff

          @entries << entry
        rescue JSON::ParserError
          next
        end
      end

      def load_all_entries
        return [] unless File.exist?(AUDIT_LOG_PATH)

        File.readlines(AUDIT_LOG_PATH).filter_map do |line|
          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end
      end

      def compute_metrics
        compute_metrics_for(@entries)
      end

      def compute_metrics_for(entries)
        {
          period: {
            start: entries.first&.dig('timestamp'),
            end: entries.last&.dig('timestamp'),
            entries: entries.count
          },
          tools: tool_metrics(entries),
          rules: rule_metrics(entries),
          results: result_distribution(entries),
          trend: compute_trend(entries)
        }
      end

      def tool_metrics(entries)
        tools = Hash.new { |h, k| h[k] = { total: 0, passed: 0, warned: 0, blocked: 0 } }

        entries.each do |entry|
          tool = entry['tool']
          result = entry['result']

          tools[tool][:total] += 1
          case result
          when 'pass'
            tools[tool][:passed] += 1
          when 'warn'
            tools[tool][:warned] += 1
          when 'block'
            tools[tool][:blocked] += 1
          end
        end

        tools.transform_values do |stats|
          stats[:pass_rate] = stats[:total].positive? ? (stats[:passed].to_f / stats[:total] * 100).round(1) : 0
          stats
        end
      end

      def rule_metrics(entries)
        rules = Hash.new { |h, k| h[k] = { checked: 0, passed: 0, warned: 0, blocked: 0 } }

        entries.each do |entry|
          (entry['rules_checked'] || []).each do |rule|
            rules[rule][:checked] += 1
            case entry['result']
            when 'pass'
              rules[rule][:passed] += 1
            when 'warn'
              rules[rule][:warned] += 1
            when 'block'
              rules[rule][:blocked] += 1
            end
          end
        end

        rules.transform_values do |stats|
          stats[:effectiveness] = calculate_effectiveness(stats)
          stats
        end
      end

      def calculate_effectiveness(stats)
        return 'N/A' if stats[:checked].zero?

        # Effectiveness = (blocked + warned) / checked * 100
        # Higher is better - means the rule is catching issues
        caught = stats[:blocked] + stats[:warned]
        return 'passive' if caught.zero? # Rule never catches anything

        "#{(caught.to_f / stats[:checked] * 100).round(1)}%"
      end

      def result_distribution(entries)
        dist = Hash.new(0)
        entries.each { |e| dist[e['result']] += 1 }
        total = entries.count.to_f

        dist.transform_values do |count|
          {
            count: count,
            percentage: total.positive? ? (count / total * 100).round(1) : 0
          }
        end
      end

      def compute_trend(entries)
        return 'insufficient_data' if entries.count < 10

        # Split entries into two halves and compare block/warn rates
        mid = entries.count / 2
        first_half = entries[0...mid]
        second_half = entries[mid..]

        first_issues = count_issues(first_half)
        second_issues = count_issues(second_half)

        first_rate = first_half.any? ? first_issues.to_f / first_half.count : 0
        second_rate = second_half.any? ? second_issues.to_f / second_half.count : 0

        if second_rate < first_rate * 0.8
          'improving'
        elsif second_rate > first_rate * 1.2
          'degrading'
        else
          'stable'
        end
      end

      def count_issues(entries)
        entries.count { |e| %w[warn block].include?(e['result']) }
      end

      def save_metrics(metrics)
        FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))
        File.write(OUTPUT_PATH, JSON.pretty_generate(metrics))
      end
    end
  end
end
