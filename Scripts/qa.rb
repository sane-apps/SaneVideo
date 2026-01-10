#!/usr/bin/env ruby
# frozen_string_literal: true

#
# SaneVideo QA Script
# Automated product verification before release
#
# Usage: ruby ./Scripts/qa.rb
#
# Checks:
# - All hooks exist and have valid Ruby syntax
# - README/DEVELOPMENT docs exist
# - .claude/settings.json registers the expected hook entrypoints
# - All hooks use stdin pattern (not ENV vars)
# - SaneMaster CLI and modules have valid syntax
# - Hook tests pass
#

require 'English'
require 'net/http'
require 'uri'
require 'json'

class SaneVideoQA
  HOOKS_DIR = File.join(__dir__, 'hooks')
  README = File.join(__dir__, '..', 'README.md')
  SOP_DOC = File.join(__dir__, '..', 'DEVELOPMENT.md')
  HOOKS_README = File.join(__dir__, 'hooks', 'README.md')
  SETTINGS_JSON = File.join(__dir__, '..', '.claude', 'settings.json')

  AI_AGENT_QUICK_START = File.join(__dir__, '..', 'AI_AGENT_QUICK_START.md')

  # Hooks that get registered in settings.json
  EXPECTED_HOOKS = %w[
    session_start.rb
    saneprompt.rb
    sanetools.rb
    sanetrack.rb
    sanestop.rb
  ].freeze

  # Shared modules that hooks require (not registered, but must exist)
  SHARED_MODULES = %w[
    rule_tracker.rb
    saneprompt_intelligence.rb
    sanetools_checks.rb
    state_signer.rb
  ].freeze

  # All hook files that should exist
  ALL_HOOK_FILES = (EXPECTED_HOOKS + SHARED_MODULES).freeze

  SANEMASTER_CLI = File.join(__dir__, 'SaneMaster.rb')
  SANEMASTER_DIR = File.join(__dir__, 'sanemaster')

  EXPECTED_SANEMASTER_MODULES = %w[
    base.rb
    bootstrap.rb
    circuit_breaker_state.rb
    compliance_report.rb
    dependencies.rb
    diagnostics.rb
    export.rb
    generation.rb
    generation_assets.rb
    generation_mocks.rb
    generation_templates.rb
    md_export.rb
    memory.rb
    meta.rb
    quality.rb
    session.rb
    sop_loop.rb
    test_mode.rb
    verify.rb
  ].freeze

  def initialize
    @errors = []
    @warnings = []
  end

  def run
    puts '═══════════════════════════════════════════════════════════════'
    puts '                   SaneVideo QA Check'
    puts '═══════════════════════════════════════════════════════════════'
    puts

    check_hooks_exist
    check_hooks_syntax
    check_hooks_use_stdin
    check_hooks_registered
    check_sanemaster_syntax
    check_docs_exist
    check_sop_doc
    check_hooks_readme
    run_hook_tests

    puts
    puts '═══════════════════════════════════════════════════════════════'

    if @errors.empty? && @warnings.empty?
      puts '✅ All checks passed!'
    else
      unless @warnings.empty?
        puts "⚠️  Warnings (#{@warnings.count}):"
        @warnings.each { |w| puts "   - #{w}" }
        puts
      end

      unless @errors.empty?
        puts "❌ Errors (#{@errors.count}):"
        @errors.each { |e| puts "   - #{e}" }
        puts
        exit 1
      end

    end
    exit 0
  end

  private

  def check_hooks_exist
    print 'Checking hooks exist... '

    missing = ALL_HOOK_FILES.reject do |hook|
      File.exist?(File.join(HOOKS_DIR, hook))
    end

    if missing.empty?
      puts "✅ #{ALL_HOOK_FILES.count} hooks present"
    else
      @errors << "Missing hooks: #{missing.join(', ')}"
      puts "❌ Missing: #{missing.join(', ')}"
    end
  end

  def check_hooks_syntax
    print 'Checking Ruby syntax... '

    invalid = []
    ALL_HOOK_FILES.each do |hook|
      path = File.join(HOOKS_DIR, hook)
      next unless File.exist?(path)

      `ruby -c #{path} 2>&1`
      invalid << hook unless $CHILD_STATUS.success?
    end

    if invalid.empty?
      puts '✅ All hooks have valid syntax'
    else
      @errors << "Invalid syntax in: #{invalid.join(', ')}"
      puts "❌ Invalid: #{invalid.join(', ')}"
    end
  end

  def check_hooks_use_stdin
    print 'Checking hooks use stdin for input... '

    uses_env_for_input = []
    EXPECTED_HOOKS.each do |hook|
      path = File.join(HOOKS_DIR, hook)
      next unless File.exist?(path)

      content = File.read(path)
      # Check for deprecated patterns: ENV['CLAUDE_TOOL_INPUT'] or ENV['CLAUDE_TOOL_OUTPUT']
      # These should use stdin instead. CLAUDE_PROJECT_DIR and CLAUDE_SESSION_ID are OK.
      next unless content.match?(/ENV\[['"]CLAUDE_TOOL_INPUT/) ||
                  content.match?(/ENV\.fetch\(['"]CLAUDE_TOOL_INPUT/) ||
                  content.match?(/ENV\[['"]CLAUDE_TOOL_OUTPUT/) ||
                  content.match?(/ENV\.fetch\(['"]CLAUDE_TOOL_OUTPUT/)

      uses_env_for_input << hook
    end

    if uses_env_for_input.empty?
      puts '✅ All hooks use stdin'
    else
      @errors << "Hooks using ENV for tool input (should use stdin): #{uses_env_for_input.join(', ')}"
      puts "❌ Using ENV for input: #{uses_env_for_input.join(', ')}"
    end
  end

  def check_hooks_registered
    print 'Checking hooks registered in settings.json... '

    unless File.exist?(SETTINGS_JSON)
      @errors << 'settings.json not found'
      puts '❌ Missing'
      return
    end

    begin
      settings = JSON.parse(File.read(SETTINGS_JSON))
    rescue JSON::ParserError => e
      @errors << "settings.json is invalid JSON: #{e.message}"
      puts '❌ Invalid JSON'
      return
    end

    hooks_section = settings['hooks'] || {}

    # Extract all hook commands from settings.json
    registered_hooks = []
    %w[UserPromptSubmit SessionStart PreToolUse PostToolUse].each do |hook_type|
      entries = hooks_section[hook_type] || []
      entries.each do |entry|
        hook_list = entry['hooks'] || []
        hook_list.each do |hook|
          command = hook['command'] || ''
          # Extract hook filename from command like: ruby ./Scripts/hooks/saneprompt.rb
          if (match = command.match(%r{hooks/([^/\s"]+\.rb)}))
            registered_hooks << match[1]
          end
        end
      end
    end

    registered_hooks.uniq!

    # Check which expected hooks are NOT registered
    not_registered = EXPECTED_HOOKS - registered_hooks

    if not_registered.empty?
      puts "✅ All #{EXPECTED_HOOKS.count} hooks registered"
    else
      @errors << "Hooks NOT registered in settings.json (invisible!): #{not_registered.join(', ')}"
      puts "❌ Not registered: #{not_registered.join(', ')}"
    end
  end

  def check_sanemaster_syntax
    print 'Checking SaneMaster syntax... '

    invalid = []

    # Check main CLI
    if File.exist?(SANEMASTER_CLI)
      result = `ruby -c #{SANEMASTER_CLI} 2>&1`
      invalid << 'SaneMaster.rb' unless $CHILD_STATUS.success?
    else
      @errors << 'SaneMaster.rb not found'
      puts '❌ Missing'
      return
    end

    # Check all modules exist and have valid syntax
    missing_modules = []
    EXPECTED_SANEMASTER_MODULES.each do |mod|
      path = File.join(SANEMASTER_DIR, mod)
      unless File.exist?(path)
        missing_modules << mod
        next
      end

      result = `ruby -c #{path} 2>&1`
      invalid << mod unless $CHILD_STATUS.success?
    end

    if missing_modules.any?
      @errors << "Missing SaneMaster modules: #{missing_modules.join(', ')}"
      puts "❌ Missing modules: #{missing_modules.join(', ')}"
      return
    end

    if invalid.empty?
      puts "✅ SaneMaster + #{EXPECTED_SANEMASTER_MODULES.count} modules valid"
    else
      @errors << "Invalid syntax in SaneMaster: #{invalid.join(', ')}"
      puts "❌ Invalid: #{invalid.join(', ')}"
    end
  end

  def check_init_script
    print 'Checking init.sh... '
    puts '⚠️  Not used in SaneVideo (skipping)'
  end

  def check_readme_hook_count
    print 'Checking README.md hook count... '

    unless File.exist?(README)
      @warnings << 'README.md not found'
      puts '⚠️  Not found'
      return
    end

    content = File.read(README)

    # Look for patterns like "11 SOP enforcement hooks" or "11 production-ready hooks"
    hook_counts = content.scan(/(\d+)\s+(?:SOP enforcement |production-ready )?hooks?/i).flatten.map(&:to_i)

    if hook_counts.empty?
      @warnings << 'README.md: No hook count found'
      puts '⚠️  No count found'
      return
    end

    wrong_counts = hook_counts.reject { |c| c == ALL_HOOK_FILES.count }
    if wrong_counts.empty?
      puts "✅ Hook count correct (#{ALL_HOOK_FILES.count})"
    else
      @errors << "README.md says #{wrong_counts.first} hooks, should be #{ALL_HOOK_FILES.count}"
      puts "❌ Says #{wrong_counts.first}, should be #{ALL_HOOK_FILES.count}"
    end
  end

  def check_docs_exist
    print 'Checking required docs exist... '

    missing = []
    missing << 'README.md' unless File.exist?(README)
    missing << 'DEVELOPMENT.md' unless File.exist?(SOP_DOC)
    missing << 'AI_AGENT_QUICK_START.md' unless File.exist?(AI_AGENT_QUICK_START)

    if missing.empty?
      puts '✅ OK'
    else
      @errors << "Missing docs: #{missing.join(', ')}"
      puts "❌ Missing: #{missing.join(', ')}"
    end
  end

  def check_sop_doc
    print 'Checking DEVELOPMENT.md (SOP)... '

    unless File.exist?(SOP_DOC)
      @errors << 'DEVELOPMENT.md not found'
      puts '❌ Missing'
      return
    end

    content = File.read(SOP_DOC)
    if content.include?('## 1. The Golden Rules')
      puts '✅ Found Golden Rules section'
    else
      @warnings << 'DEVELOPMENT.md: Golden Rules section not found'
      puts '⚠️  Golden Rules section not found'
    end
  end

  def check_hooks_readme
    print 'Checking hooks/README.md... '

    unless File.exist?(HOOKS_README)
      @warnings << 'hooks/README.md not found'
      puts '⚠️  Not found'
      return
    end

    content = File.read(HOOKS_README)

    # Check each expected hook entrypoint is mentioned
    missing = EXPECTED_HOOKS.reject { |hook| content.include?(hook) }

    if missing.empty?
      puts '✅ All hooks documented'
    else
      @errors << "hooks/README.md missing: #{missing.join(', ')}"
      puts "❌ Missing docs: #{missing.join(', ')}"
    end
  end

  def check_version_consistency
    print 'Checking version consistency... '

    puts '⚠️  Not enforced in SaneVideo (skipping)'
  end

  def check_urls
    print 'Checking URLs in docs... '

    urls_to_check = []

    # Collect URLs from key files
    [README, SOP_DOC, AI_AGENT_QUICK_START, File.join(__dir__, '..', '.claude', 'SOP_CONTEXT.md')].each do |file|
      next unless File.exist?(file)

      content = File.read(file)
      # Extract URLs
      content.scan(%r{https?://[^\s)\]"']+}).each do |url|
        # Skip localhost, example.com, placeholder URLs
        next if url.include?('localhost')
        next if url.include?('example.com')
        next if url.include?('XXXX')
        next if url.include?('<')

        urls_to_check << { url: url.gsub(/[,.]$/, ''), file: File.basename(file) }
      end
    end

    if urls_to_check.empty?
      puts '⚠️  No URLs found'
      return
    end

    bad_urls = []
    urls_to_check.uniq { |u| u[:url] }.each do |entry|
      uri = URI.parse(entry[:url])
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 5
      http.read_timeout = 5

      response = http.head(uri.request_uri)
      # Accept 2xx, 3xx, 404 for GitHub raw URLs that may not exist yet
      unless response.code.to_i < 400 || (response.code.to_i == 404 && entry[:url].include?('raw.githubusercontent'))
        bad_urls << "#{entry[:url]} (#{response.code}) in #{entry[:file]}"
      end
    rescue StandardError => e
      bad_urls << "#{entry[:url]} (#{e.class.name}) in #{entry[:file]}"
    end

    if bad_urls.empty?
      puts "✅ #{urls_to_check.count} URLs reachable"
    else
      bad_urls.each { |u| @warnings << "Unreachable URL: #{u}" }
      puts "⚠️  #{bad_urls.count} unreachable"
    end
  end

  def run_hook_tests
    print 'Running hook tests... '

    test_file = File.join(HOOKS_DIR, 'test', 'hook_test.rb')
    unless File.exist?(test_file)
      @warnings << "Hook tests not found at #{test_file}"
      puts '⚠️  Tests not found'
      return
    end

    result = `ruby #{test_file} 2>&1`
    if $CHILD_STATUS.success?
      # Extract test count from output
      if result.match?(/(\d+) tests.*0 failures/)
        puts '✅ All tests pass'
      else
        puts '✅ Tests pass'
      end
    else
      @errors << 'Hook tests failed'
      puts '❌ Tests failed'
      puts result.lines.last(5).join if result.lines.any?
    end
  end
end

# Run if executed directly
SaneVideoQA.new.run if __FILE__ == $PROGRAM_NAME
