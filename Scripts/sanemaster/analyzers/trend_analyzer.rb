# frozen_string_literal: true

module SaneMasterModules
  module Analyzers
    # Compares collaboration quality across sessions over time
    class TrendAnalyzer
      INTERVENTIONS_PATH = File.expand_path('~/.claude/collab/interventions.jsonl')
      METRICS_PATH = File.expand_path('~/.claude/collab/hook_metrics.json')

      def analyze(options = {})
        days_back = options[:days] || 30

        {
          intervention_trend: intervention_trend(days_back),
          session_comparison: session_comparison(days_back),
          improvement_areas: improvement_areas,
          overall_trend: overall_trend(days_back)
        }
      end

      def intervention_trend(days_back)
        interventions = load_interventions
        return { error: 'No intervention data' } if interventions.empty?

        cutoff = Time.now - (days_back * 24 * 60 * 60)
        recent = interventions.select do |i|
          ts = begin
            Time.parse(i['timestamp'])
          rescue StandardError
            nil
          end
          ts && ts > cutoff
        end

        # Group by day
        by_day = recent.group_by do |i|
          Time.parse(i['timestamp']).strftime('%Y-%m-%d')
        rescue StandardError
          'unknown'
        end

        daily_counts = by_day.transform_values(&:count).sort.to_h

        {
          total: recent.count,
          daily_average: recent.count.to_f / [days_back, daily_counts.count].min,
          daily_counts: daily_counts,
          direction: calculate_direction(daily_counts.values)
        }
      end

      def session_comparison(_days_back)
        interventions = load_interventions
        return { error: 'No data' } if interventions.empty?

        # Group by session
        by_session = interventions.group_by { |i| i['session'] }

        sessions = by_session.map do |session_id, items|
          timestamps = items.filter_map do |i|
            Time.parse(i['timestamp'])
          rescue StandardError
            nil
          end
          next nil if timestamps.empty?

          {
            session: session_id&.[](0, 8), # Truncate UUID
            date: timestamps.min.strftime('%Y-%m-%d'),
            interventions: items.count,
            high_severity: items.count { |i| i['signal'] == 'high' },
            patterns: items.map { |i| i['pattern'] }.tally
          }
        end.compact

        # Sort by date descending
        sessions.sort_by { |s| s[:date] }.reverse.first(10)
      end

      def improvement_areas
        interventions = load_interventions
        return [] if interventions.empty?

        # Find patterns that keep recurring
        pattern_freq = interventions.map { |i| i['pattern'] }.tally
        context_freq = interventions.map { |i| i['context'] }.tally

        # Patterns with 3+ occurrences
        areas = pattern_freq.select { |_, count| count >= 3 }.map do |pattern, count|
          {
            type: 'recurring_pattern',
            name: pattern,
            occurrences: count,
            recommendation: pattern_recommendation(pattern)
          }
        end

        # Contexts with 3+ occurrences
        context_freq.select { |_, count| count >= 3 }.each do |context, count|
          areas << {
            type: 'problem_area',
            name: context,
            occurrences: count,
            recommendation: context_recommendation(context)
          }
        end

        areas.sort_by { |a| -a[:occurrences] }
      end

      def overall_trend(days_back)
        int_trend = intervention_trend(days_back)
        return 'insufficient_data' if int_trend[:error]

        direction = int_trend[:direction]
        avg = int_trend[:daily_average]

        if direction == 'decreasing' && avg < 1
          { status: 'excellent', message: 'Collaboration quality is improving' }
        elsif direction == 'stable' && avg < 2
          { status: 'good', message: 'Stable collaboration with minor corrections' }
        elsif direction == 'increasing' || avg > 3
          { status: 'needs_attention', message: 'Increasing corrections - review patterns' }
        else
          { status: 'moderate', message: 'Room for improvement' }
        end
      end

      private

      def load_interventions
        return [] unless File.exist?(INTERVENTIONS_PATH)

        File.readlines(INTERVENTIONS_PATH).filter_map do |line|
          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end
      end

      def calculate_direction(values)
        return 'insufficient_data' if values.count < 3

        # Simple linear regression
        n = values.count
        first_half_avg = values[0...(n / 2)].sum.to_f / (n / 2)
        second_half_avg = values[(n / 2)..].sum.to_f / (n - (n / 2))

        if second_half_avg < first_half_avg * 0.8
          'decreasing'
        elsif second_half_avg > first_half_avg * 1.2
          'increasing'
        else
          'stable'
        end
      end

      def pattern_recommendation(pattern)
        case pattern
        when 'direct_correction', 'explicit_error'
          'Add verification step before acting'
        when 'frustration'
          'Strengthen SOP check at session start'
        when 'repeated_instruction'
          'Create persistent reminder hook'
        when 'redirect'
          'Gather more context before proceeding'
        else
          'Review and add specific guardrail'
        end
      end

      def context_recommendation(context)
        case context
        when 'screenshot'
          'Add hook to check screenshot location'
        when 'sop'
          'Display SOP context more prominently'
        when 'memory'
          'Automate memory check at session start'
        when 'build', 'test'
          'Enforce full verify cycle'
        when 'path', 'version'
          'Add path/version verification hook'
        else
          'Add context-specific validation'
        end
      end
    end
  end
end
