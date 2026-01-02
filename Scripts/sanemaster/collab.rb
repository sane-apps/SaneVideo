# frozen_string_literal: true

require_relative 'analyzers/intervention_analyzer'
require_relative 'analyzers/hook_metrics'
require_relative 'analyzers/trend_analyzer'

module SaneMasterModules
  # Collaboration observability dashboard
  module Collab
    extend self

    def run(args = [])
      case args.first
      when 'interventions', 'i'
        show_interventions(args[1..])
      when 'hooks', 'h'
        show_hook_metrics(args[1..])
      when 'trends', 't'
        show_trends(args[1..])
      when 'suggestions', 's'
        show_suggestions
      when 'analyze', 'a'
        run_analysis
      else
        show_dashboard
      end
    end

    private

    def show_dashboard
      puts header('COLLABORATION REPORT')
      puts ''

      # Session summary from hook metrics
      show_session_summary

      # Intervention summary
      show_intervention_summary

      # Hook effectiveness
      show_hook_effectiveness

      # Automation suggestions
      show_automation_suggestions

      puts ''
      puts '  Commands:'
      puts '    collab interventions  - Detailed intervention list'
      puts '    collab hooks          - Hook metrics breakdown'
      puts '    collab trends         - Trend analysis'
      puts '    collab suggestions    - Automation suggestions'
      puts '    collab analyze        - Re-analyze all data'
      puts ''
    end

    def show_session_summary
      metrics = Analyzers::HookMetrics.new.current_session_metrics
      return puts "  No session data available.\n\n" if metrics.empty? || metrics[:error]

      period = metrics[:period] || {}
      tools = metrics[:tools] || {}

      puts section_header('SESSION SUMMARY')

      tool_summary = tools.map { |t, s| "#{t} (#{s[:total]})" }.join(', ')
      puts "   Tools used: #{tool_summary}"

      results = metrics[:results] || {}
      passed = results.dig('pass', :count) || 0
      warned = results.dig('warn', :count) || 0
      blocked = results.dig('block', :count) || 0
      total = period[:entries] || 0

      puts "   Rules checked: #{total} | Passed: #{passed} | Warned: #{warned} | Blocked: #{blocked}"
      puts ''
    end

    def show_intervention_summary
      analyzer = Analyzers::InterventionAnalyzer.new
      recent = analyzer.recent_interventions(5)

      puts section_header('INTERVENTIONS DETECTED', count: recent.count)

      if recent.empty?
        puts '   No interventions detected in recent sessions.'
      else
        recent.each_with_index do |int, i|
          severity = int['signal'] == 'high' ? '[HIGH]' : '[MED] '
          pattern = int['pattern']&.gsub('_', ' ') || 'unknown'
          context = int['context'] || ''
          puts "   #{i + 1}. #{severity} #{pattern} - #{context}"
        end
      end
      puts ''
    end

    def show_hook_effectiveness
      metrics = Analyzers::HookMetrics.new.analyze(days: 7)
      return if metrics[:error]

      rules = metrics[:rules] || {}
      trend = metrics[:trend] || 'unknown'

      puts section_header('HOOK EFFECTIVENESS', subtitle: 'last 7 days')
      puts '   Rule                  Fire Rate   Block %   Trend'
      puts '   ' + ('-' * 50)

      rules.each do |rule, stats|
        name = rule.ljust(20)[0, 20]
        fire_rate = '100%'.rjust(8)
        block_pct = calculate_block_pct(stats)
        trend_indicator = trend_icon(trend)
        puts "   #{name} #{fire_rate}   #{block_pct.rjust(6)}    #{trend_indicator}"
      end

      puts '   No rule data available.' if rules.empty?
      puts ''
    end

    def show_automation_suggestions
      analyzer = Analyzers::InterventionAnalyzer.new
      suggestions = analyzer.suggestions(3) # Threshold of 3

      puts section_header('AUTOMATION SUGGESTIONS')

      if suggestions.empty?
        puts '   No patterns detected 3+ times yet.'
      else
        suggestions.first(3).each do |sug|
          puts "   Pattern \"#{sug[:pattern]}\" detected #{sug[:count]}x"
          puts "   -> #{sug[:suggestion]}"
          puts "   -> Run: ./Scripts/SaneMaster.rb generate_hook #{sug[:pattern]}"
          puts ''
        end
      end
    end

    def show_interventions(args)
      analyzer = Analyzers::InterventionAnalyzer.new
      limit = args.first&.to_i || 20
      interventions = analyzer.recent_interventions(limit)

      puts header('INTERVENTION DETAILS')
      puts ''

      if interventions.empty?
        puts '  No interventions recorded.'
        return
      end

      interventions.reverse.each do |int|
        ts = int['timestamp'] ? Time.parse(int['timestamp']).strftime('%m/%d %H:%M') : '?'
        severity = int['signal']&.upcase || '?'
        pattern = int['pattern'] || 'unknown'
        context = int['context'] || ''
        msg = int['user_message']&.[](0, 60) || ''

        puts "  [#{ts}] #{severity.ljust(6)} #{pattern.ljust(20)} #{context}"
        puts "    \"#{msg}#{'...' if msg.length >= 60}\""
        puts ''
      end

      # Frequency summary
      freq = analyzer.pattern_frequency
      puts section_header('PATTERN FREQUENCY')
      freq.first(5).each do |pattern, count|
        bar = '*' * [count, 20].min
        puts "   #{pattern.ljust(25)} #{count.to_s.rjust(3)} #{bar}"
      end
      puts ''
    end

    def show_hook_metrics(args)
      days = args.first&.to_i || 7
      metrics = Analyzers::HookMetrics.new.analyze(days: days)

      puts header("HOOK METRICS (#{days} days)")
      puts ''

      if metrics[:error]
        puts "  Error: #{metrics[:error]}"
        puts "  Path: #{metrics[:path]}"
        return
      end

      # Tools breakdown
      puts section_header('TOOLS')
      (metrics[:tools] || {}).each do |tool, stats|
        puts "   #{tool.ljust(10)} Total: #{stats[:total].to_s.rjust(4)} | " \
             "Pass: #{stats[:passed]} | Warn: #{stats[:warned]} | Block: #{stats[:blocked]} | " \
             "Rate: #{stats[:pass_rate]}%"
      end
      puts ''

      # Rules breakdown
      puts section_header('RULES')
      (metrics[:rules] || {}).each do |rule, stats|
        puts "   #{rule.ljust(20)} Checked: #{stats[:checked].to_s.rjust(3)} | " \
             "Effectiveness: #{stats[:effectiveness]}"
      end
      puts ''

      # Overall trend
      puts "  Trend: #{trend_icon(metrics[:trend])} #{metrics[:trend]}"
      puts ''
    end

    def show_trends(args)
      days = args.first&.to_i || 30
      analyzer = Analyzers::TrendAnalyzer.new
      trends = analyzer.analyze(days: days)

      puts header("TREND ANALYSIS (#{days} days)")
      puts ''

      # Intervention trend
      int_trend = trends[:intervention_trend]
      unless int_trend[:error]
        puts section_header('INTERVENTION TREND')
        puts "   Total: #{int_trend[:total]} | Daily avg: #{int_trend[:daily_average].round(1)} | " \
             "Direction: #{trend_icon(int_trend[:direction])} #{int_trend[:direction]}"
        puts ''
      end

      # Session comparison
      sessions = trends[:session_comparison]
      if sessions.is_a?(Array) && sessions.any?
        puts section_header('RECENT SESSIONS')
        sessions.first(5).each do |s|
          puts "   #{s[:date]} (#{s[:session]}) - #{s[:interventions]} interventions " \
               "(#{s[:high_severity]} high)"
        end
        puts ''
      end

      # Improvement areas
      areas = trends[:improvement_areas]
      if areas.any?
        puts section_header('IMPROVEMENT AREAS')
        areas.first(5).each do |area|
          puts "   #{area[:type]}: #{area[:name]} (#{area[:occurrences]}x)"
          puts "   -> #{area[:recommendation]}"
          puts ''
        end
      end

      # Overall
      overall = trends[:overall_trend]
      puts "  Overall: #{status_icon(overall[:status])} #{overall[:message]}" if overall.is_a?(Hash)
      puts ''
    end

    def show_suggestions
      analyzer = Analyzers::InterventionAnalyzer.new
      suggestions = analyzer.suggestions(2) # Lower threshold for detailed view

      puts header('AUTOMATION SUGGESTIONS')
      puts ''

      if suggestions.empty?
        puts '  No patterns detected frequently enough to suggest automation.'
        puts '  Threshold: 2+ occurrences of the same pattern.'
        return
      end

      suggestions.each do |sug|
        puts "  Pattern: #{sug[:pattern]}"
        puts "  Occurrences: #{sug[:count]}"
        puts "  Suggestion: #{sug[:suggestion]}"
        puts "  Generate: ./Scripts/SaneMaster.rb generate_hook #{sug[:pattern]}"
        puts ''
      end
    end

    def run_analysis
      puts header('RUNNING ANALYSIS')
      puts ''

      print '  Analyzing conversation history... '
      int_result = Analyzers::InterventionAnalyzer.new.analyze(days: 30)
      puts "#{int_result[:total]} interventions found"

      print '  Aggregating hook metrics... '
      hook_result = Analyzers::HookMetrics.new.analyze(days: 7)
      puts hook_result[:error] ? "Error: #{hook_result[:error]}" : 'Done'

      print '  Computing trends... '
      Analyzers::TrendAnalyzer.new.analyze(days: 30)
      puts 'Done'

      puts ''
      puts '  Analysis complete. Run `collab` to see the dashboard.'
      puts ''
    end

    # Formatting helpers

    def header(title)
      line = '=' * 60
      "\n  #{line}\n  #{title.center(60)}\n  #{line}"
    end

    def section_header(title, count: nil, subtitle: nil)
      suffix = count ? ": #{count}" : ''
      suffix += " (#{subtitle})" if subtitle
      "  #{title}#{suffix}"
    end

    def trend_icon(trend)
      case trend.to_s
      when 'improving', 'decreasing'
        "\u2193" # Down arrow (fewer issues = better)
      when 'degrading', 'increasing'
        "\u2191" # Up arrow (more issues = worse)
      when 'stable'
        "\u2194" # Left-right arrow
      else
        '?'
      end
    end

    def status_icon(status)
      case status.to_s
      when 'excellent'
        "\u2705" # Green check
      when 'good'
        "\u2714" # Check mark
      when 'moderate'
        "\u26A0" # Warning
      when 'needs_attention'
        "\u274C" # Red X
      else
        '?'
      end
    end

    def calculate_block_pct(stats)
      total = stats[:checked] || 0
      blocked = stats[:blocked] || 0
      return '0%' if total.zero?

      "#{(blocked.to_f / total * 100).round(1)}%"
    end
  end
end
