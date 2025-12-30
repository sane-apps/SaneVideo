#!/usr/bin/env ruby
# frozen_string_literal: true

require 'English'
require 'json'
require 'fileutils'
require 'tmpdir'
require 'optparse'
require 'set'
require 'time'

# ==============================================================================
# SaneMaster: Professional Automation Suite for SaneVideo
# ==============================================================================
# Commands:
#   diagnose [path] - Run intelligent heuristics on a .xcresult bundle.
#   doctor          - Check environment, mock assets, and permissions.
#   verify [--ui]   - Build and run tests (unit tests only by default, --ui for UI tests).
#   clean           - Safely wipe build cache and test states.
#   reset           - Wipe TCC privacy permissions (Camera, Mic, Screen).
#   audit           - Scan project for missing accessibility identifiers.
#   setup           - Install missing gems and system dependencies.
#   lint            - Run SwiftLint and auto-fix common issues.
#   quality         - Generate Ruby quality reports (HTML).
#   gen_test        - Generate test file from template (NEW)
#   gen_mock        - Generate mocks using Mockolo (NEW)
# ==============================================================================

class SaneMaster
  def initialize
    @bundle_id = 'com.sanevideo.SaneVideo' # Centralized for tccutil
  end

  # --- Launch Application ---

  def launch_app(args)
    puts '🚀 --- [ SANEMASTER LAUNCH ] ---'

    # Check if app exists
    app_path = Dir.glob(File.join(File.expand_path('~/Library/Developer/Xcode/DerivedData/SaneVideo-*/Build/Products/Debug'), 'SaneVideo.app')).first

    unless app_path && File.exist?(app_path)
      puts '❌ App binary not found. Run ./Scripts/SaneMaster.rb verify to build.'
      return
    end

    puts "📱 Launching: #{app_path}"

    # Handle arguments
    capture_logs = args.include?('--logs')
    env_vars = {}

    # Pass through VERIFY_PIP if set in current env
    env_vars['VERIFY_PIP'] = ENV['VERIFY_PIP'] if ENV['VERIFY_PIP']

    if capture_logs
      puts '📝 Capturing logs to stdout...'
      pid = spawn(env_vars, "#{app_path}/Contents/MacOS/SaneVideo")
      Process.wait(pid)
    else
      system(env_vars, "open '#{app_path}'")
      puts '✅ App launched'
    end
  end

  def run(args)
    if args.empty?
      print_help
      return
    end

    command = args.shift
    case command
    when 'diagnose'
      path = nil
      dump = false

      # Simple arg parsing
      args.each_with_index do |arg, i|
        if arg == '--path'
          path = args[i + 1]
        elsif arg == '--dump'
          dump = true
        elsif !arg.start_with?('-') && path.nil?
          path = arg
        end
      end

      diagnose(path, dump: dump)
    when 'doctor'   then doctor
    when 'verify'   then verify(args)
    when 'clean'    then clean(args)
    when 'reset'    then reset_permissions
    when 'check_permissions' then check_permission_status
    when 'audit' then audit_project
    when 'validate_test_references', 'validate-tests' then validate_test_references
    when 'setup'    then setup_environment
    when 'lint'     then run_lint
    when 'quality'  then run_quality_report
    when 'check_binary' then check_binary
    when 'restore' then restore_xcode
    when 'verify_mcps' then verify_mcps
    when 'gen_assets' then generate_test_assets
    when 'gen_test' then generate_test_file(args)
    when 'gen_mock' then generate_mocks(args)
    when 'check_xcodegen' then check_xcodegen(args)
    when 'verify_api' then verify_api(args)
    when 'verify_mocks' then verify_mocks
    when 'check_protocol_changes' then check_protocol_changes(args)
    when 'check_docs' then verify_documentation_sync
    when 'dead_code', 'find_dead_code' then find_dead_code
    when 'check_deprecations', 'deprecations' then check_deprecations
    when 'swift6_check', 'swift6', 'concurrency_check' then swift6_check
    when 'test_suite', 'suite' then run_test_suite(args)
    when 'crash_report', 'crashes' then analyze_crashes(args)
    when 'launch', 'run' then launch_app(args)
    when 'logs' then show_app_logs(args)
    when 'test_mode', 'tm' then enter_test_mode(args)
    when 'bootstrap', 'preflight', 'env' then run_bootstrap(args)
    when 'version_check', 'versions' then check_latest_versions(args)
    when 'ci_parity', 'ci_check' then check_ci_parity
    when 'deps', 'dependencies' then show_dependency_graph(args)
    when 'template' then manage_templates(args)
    when 'console'
      require 'pry'
      # rubocop:disable Lint/Debugger
      binding.pry
      # rubocop:enable Lint/Debugger
    else
      puts "❌ Unknown command: #{command}"
      print_help
    end
  end

  # --- PRO Commands ---

  def restore_xcode
    puts '🛠️ --- [ SANEMASTER RESTORE ] ---'
    puts 'Fixing common Xcode/Launch Services issues...'

    # 1. Reset Launch Services
    lsregister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
    if File.exist?(lsregister)
      print '  Resetting Launch Services database... '
      system("#{lsregister} -kill -r -domain local -domain system -domain user")
      puts '✅'
    end

    # 2. Restart Dock (often helps with icon/launch issues)
    print '  Restarting Dock... '
    system('killall Dock')
    puts '✅'

    # 3. Nuclear Clean
    clean(['--nuclear'])

    puts "\n✅ System restored. Try opening the project in Xcode again."
  end

  def setup_environment
    puts '🛠️ --- [ SANEMASTER SETUP ] ---'

    print '📦 Running bundle install... '
    if system('bundle install --path vendor/bundle > /dev/null 2>&1')
      puts '✅'
    else
      puts '⚠️  Bundle install failed or not needed'
    end

    print '🔍 Checking SwiftFormat... '
    if system('which swiftformat > /dev/null 2>&1')
      puts '✅'
    else
      puts '⚠️  SwiftFormat not found. Install: brew install swiftformat'
    end

    print '🔍 Checking SwiftLint... '
    if system('which swiftlint > /dev/null 2>&1')
      puts '✅'
    else
      puts '⚠️  SwiftLint not found. Install: brew install swiftlint'
    end

    puts "\n✅ Setup complete."
  end

  # =============================================================================
  # SOP Bootstrap - Full environment setup with auto-update and rollback
  # =============================================================================

  SOP_SNAPSHOT_DIR = File.expand_path('~/.sanemaster/snapshots')
  SOP_LOG_DIR = File.expand_path('~/.sanemaster/logs')
  HOMEBREW_RUBY = '/opt/homebrew/opt/ruby/bin/ruby'
  HOMEBREW_BUNDLE = '/opt/homebrew/opt/ruby/bin/bundle'

  # Known latest versions (updated periodically)
  TOOL_VERSIONS = {
    'swiftlint' => { cmd: 'swiftlint --version', min: '0.62.0' },
    'xcodegen' => { cmd: 'xcodegen --version', extract: /Version: ([\d.]+)/, min: '2.44.0' },
    'periphery' => { cmd: 'periphery version', min: '3.2.0' },
    'mockolo' => { cmd: 'mockolo --version', min: '2.4.0' },
    'lefthook' => { cmd: 'lefthook --version', extract: /lefthook version ([\d.]+)/, min: '2.0.0' }
  }.freeze

  def run_bootstrap(args)
    check_only = args.include?('--check-only')
    rollback = args.include?('--rollback')

    puts '🚀 --- [ SANEMASTER BOOTSTRAP ] ---'
    puts "Mode: #{if check_only
                    'CHECK ONLY'
                  else
                    rollback ? 'ROLLBACK' : 'FULL UPDATE'
                  end}"
    puts ''

    # Initialize logging
    ensure_sop_dirs
    @sop_log = File.join(SOP_LOG_DIR, "sop_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
    sop_log("SOP Bootstrap started - #{if check_only
                                         'check-only'
                                       else
                                         rollback ? 'rollback' : 'full-update'
                                       end}")

    if rollback
      perform_rollback
      return
    end

    # Create snapshot before making changes
    create_snapshot unless check_only

    results = {
      ruby: check_ruby_environment(check_only),
      bundle: check_bundle(check_only),
      homebrew_tools: check_homebrew_tools(check_only),
      claude_plugins: check_claude_plugins,
      mcp_servers: check_mcp_config,
      doctor: nil
    }

    # Run doctor at the end
    puts "\n📋 Running doctor health check..."
    results[:doctor] = doctor_silent

    # Print summary
    print_sop_summary(results, check_only)

    # Log completion
    sop_log("SOP Bootstrap completed - #{results.values.all? { |r| [:ok, true].include?(r) } ? 'SUCCESS' : 'ISSUES FOUND'}")
  end

  def ensure_sop_dirs
    FileUtils.mkdir_p(SOP_SNAPSHOT_DIR)
    FileUtils.mkdir_p(SOP_LOG_DIR)
  end

  def sop_log(message)
    return unless @sop_log

    File.open(@sop_log, 'a') { |f| f.puts "[#{Time.now.strftime('%H:%M:%S')}] #{message}" }
  end

  def create_snapshot
    puts '📸 Creating configuration snapshot...'
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    snapshot_dir = File.join(SOP_SNAPSHOT_DIR, timestamp)
    FileUtils.mkdir_p(snapshot_dir)

    # Snapshot key files
    files_to_snapshot = %w[
      Gemfile
      Gemfile.lock
      .ruby-version
      .claude/settings.local.json
      .mcp.json
    ]

    files_to_snapshot.each do |file|
      src = File.join(Dir.pwd, file)
      next unless File.exist?(src)

      dest_dir = File.join(snapshot_dir, File.dirname(file))
      FileUtils.mkdir_p(dest_dir)
      FileUtils.cp(src, File.join(snapshot_dir, file))
    end

    # Record tool versions
    versions = {}
    TOOL_VERSIONS.each do |tool, config|
      version = `#{config[:cmd]} 2>/dev/null`.strip
      if config[:extract]
        match = version.match(config[:extract])
        version = match[1] if match
      end
      versions[tool] = version
    end
    versions['ruby'] = begin
      `#{HOMEBREW_RUBY} --version 2>/dev/null`.strip.split[1]
    rescue StandardError
      'unknown'
    end

    File.write(File.join(snapshot_dir, 'versions.json'), JSON.pretty_generate(versions))

    # Update latest symlink
    latest_link = File.join(SOP_SNAPSHOT_DIR, 'latest')
    FileUtils.rm_f(latest_link)
    FileUtils.ln_s(snapshot_dir, latest_link)

    puts "   ✅ Snapshot saved: #{snapshot_dir}"
    sop_log("Snapshot created: #{snapshot_dir}")
  end

  def perform_rollback
    latest = File.join(SOP_SNAPSHOT_DIR, 'latest')
    unless File.exist?(latest)
      puts '❌ No snapshot found to rollback to'
      return
    end

    snapshot_dir = File.realpath(latest)
    puts "🔄 Rolling back to: #{snapshot_dir}"

    # Restore files
    %w[Gemfile Gemfile.lock .ruby-version].each do |file|
      src = File.join(snapshot_dir, file)
      next unless File.exist?(src)

      FileUtils.cp(src, File.join(Dir.pwd, file))
      puts "   ✅ Restored: #{file}"
    end

    # Re-run bundle install
    puts '📦 Re-installing bundle...'
    system("#{HOMEBREW_BUNDLE} install")

    puts "\n✅ Rollback complete"
    sop_log("Rollback performed from: #{snapshot_dir}")
  end

  def check_ruby_environment(check_only)
    puts '💎 Checking Ruby environment...'

    # Check if Homebrew Ruby exists
    unless File.exist?(HOMEBREW_RUBY)
      puts '   ❌ Homebrew Ruby not found. Install: brew install ruby'
      sop_log('Ruby: Homebrew Ruby not installed')
      return :missing
    end

    # Get current version
    version = `#{HOMEBREW_RUBY} --version 2>/dev/null`.strip
    puts "   Ruby: #{version}"

    # Check .ruby-version file
    ruby_version_file = File.join(Dir.pwd, '.ruby-version')
    if File.exist?(ruby_version_file)
      puts '   ✅ .ruby-version exists'
    elsif !check_only
      # Create .ruby-version
      ruby_ver = begin
        version.match(/ruby ([\d.]+)/)[1]
      rescue StandardError
        '3.4'
      end
      File.write(ruby_version_file, "#{ruby_ver}\n")
      puts "   ✅ Created .ruby-version (#{ruby_ver})"
      sop_log("Created .ruby-version: #{ruby_ver}")
    else
      puts '   ⚠️  .ruby-version missing'
    end

    # Check RubyGems version (no more 3.0.3.1 warning)
    gems_version = `#{HOMEBREW_RUBY} -e "puts Gem::VERSION" 2>/dev/null`.strip
    if Gem::Version.new(gems_version) >= Gem::Version.new('3.2.0')
      puts "   ✅ RubyGems #{gems_version}"
    else
      puts "   ⚠️  RubyGems #{gems_version} (upgrade recommended)"
    end

    sop_log("Ruby check: #{version}, RubyGems #{gems_version}")
    :ok
  end

  def check_bundle(check_only)
    puts "\n📦 Checking bundle dependencies..."

    unless File.exist?(HOMEBREW_BUNDLE)
      puts '   ❌ Homebrew bundle not found'
      return :missing
    end

    # Check if bundle is satisfied
    bundle_check = `#{HOMEBREW_BUNDLE} check 2>&1`
    if bundle_check.include?('dependencies are satisfied')
      puts '   ✅ Bundle dependencies satisfied'
      sop_log('Bundle: dependencies satisfied')
      return :ok if check_only
    end

    unless check_only
      puts '   🔄 Running bundle update...'
      if system("#{HOMEBREW_BUNDLE} update 2>&1")
        puts '   ✅ Bundle updated'
        sop_log('Bundle: updated successfully')

        # Reinstall lefthook after bundle update
        system('lefthook install -f 2>/dev/null')
      else
        puts '   ❌ Bundle update failed'
        sop_log('Bundle: update failed')
        return :failed
      end
    end

    :ok
  end

  def check_homebrew_tools(check_only)
    puts "\n🍺 Checking Homebrew tools..."

    outdated = []
    TOOL_VERSIONS.each do |tool, config|
      version_output = `#{config[:cmd]} 2>/dev/null`.strip
      current = if config[:extract]
                  match = version_output.match(config[:extract])
                  match ? match[1] : version_output
                else
                  version_output.split.first
                end

      status = if current.empty?
                 '❌ not installed'
               elsif Gem::Version.new(current.gsub(/[^\d.]/, '')) >= Gem::Version.new(config[:min])
                 '✅'
               else
                 outdated << tool
                 '⚠️  outdated'
               end

      puts "   #{tool}: #{current.empty? ? 'missing' : current} #{status}"
    end

    if outdated.any? && !check_only
      puts "\n   🔄 Updating outdated tools: #{outdated.join(', ')}"
      outdated.each do |tool|
        print "      Updating #{tool}... "
        if system("brew upgrade #{tool} 2>/dev/null || brew install #{tool} 2>/dev/null")
          puts '✅'
          sop_log("Updated: #{tool}")
        else
          puts '❌'
          sop_log("Failed to update: #{tool}")
        end
      end
    end

    sop_log("Homebrew tools check: #{outdated.empty? ? 'all current' : "outdated: #{outdated.join(', ')}"}")
    outdated.empty? ? :ok : :updated
  end

  def check_claude_plugins
    puts "\n🔌 Checking Claude Code plugins..."

    settings_file = File.expand_path('~/.claude/settings.json')
    unless File.exist?(settings_file)
      puts '   ⚠️  Claude settings not found'
      return :missing
    end

    begin
      settings = JSON.parse(File.read(settings_file))
      plugins = settings['enabledPlugins'] || {}

      required_plugins = %w[
        swift-lsp@claude-plugins-official
        code-review@claude-plugins-official
        security-guidance@claude-plugins-official
      ]

      required_plugins.each do |plugin|
        status = plugins[plugin] ? '✅ enabled' : '⚠️  not enabled'
        puts "   #{plugin.split('@').first}: #{status}"
      end

      sop_log("Claude plugins: #{plugins.keys.join(', ')}")
      :ok
    rescue JSON::ParserError => e
      puts "   ❌ Failed to parse settings: #{e.message}"
      :error
    end
  end

  def check_mcp_config
    puts "\n🔗 Checking MCP configuration..."

    # Check .mcp.json
    mcp_file = File.join(Dir.pwd, '.mcp.json')
    unless File.exist?(mcp_file)
      puts '   ❌ .mcp.json not found'
      return :missing
    end

    begin
      mcp_config = JSON.parse(File.read(mcp_file))
      servers = mcp_config['mcpServers'] || {}
      puts "   ✅ .mcp.json: #{servers.keys.count} servers configured"
      servers.each_key { |s| puts "      - #{s}" }

      # Check settings.local.json for enableAllProjectMcpServers
      local_settings = File.join(Dir.pwd, '.claude/settings.local.json')
      if File.exist?(local_settings)
        local = JSON.parse(File.read(local_settings))
        if local['enableAllProjectMcpServers']
          puts '   ✅ enableAllProjectMcpServers: true'
        else
          puts '   ⚠️  enableAllProjectMcpServers not set'
        end

        puts "   ⚠️  enabledMcpjsonServers restrictive list found (#{local['enabledMcpjsonServers'].count} servers)" if local['enabledMcpjsonServers']
      end

      sop_log("MCP: #{servers.keys.count} servers configured")
      :ok
    rescue JSON::ParserError => e
      puts "   ❌ Failed to parse MCP config: #{e.message}"
      :error
    end
  end

  def doctor_silent
    # Run key doctor checks silently
    issues = []

    # Check DerivedData size
    dd_size = begin
      `du -sh ~/Library/Developer/Xcode/DerivedData 2>/dev/null`.split.first
    rescue StandardError
      '?'
    end
    issues << "DerivedData: #{dd_size}" if dd_size.to_f > 5 # > 5GB

    # Check for stuck processes
    stuck = `pgrep -f 'xcodebuild|xctest' 2>/dev/null`.strip.split.count
    issues << "#{stuck} stuck build processes" if stuck.positive?

    # Check disk space
    available = `df -h . | tail -1 | awk '{print $4}'`.strip
    issues << "Low disk: #{available}" if available.end_with?('M') || available.to_f < 50

    issues.empty? ? :ok : issues
  end

  def print_sop_summary(results, check_only)
    puts "\n#{'=' * 60}"
    puts check_only ? '📋 SOP STATUS REPORT' : '✅ SOP BOOTSTRAP COMPLETE'
    puts '=' * 60

    summary = {
      'Ruby Environment' => results[:ruby],
      'Bundle Dependencies' => results[:bundle],
      'Homebrew Tools' => results[:homebrew_tools],
      'Claude Plugins' => results[:claude_plugins],
      'MCP Servers' => results[:mcp_servers]
    }

    summary.each do |name, status|
      icon = case status
             when :ok, true then '✅'
             when :updated then '🔄'
             when :missing, :failed, :error then '❌'
             else '⚠️'
             end
      puts "#{icon} #{name}"
    end

    # Doctor issues
    if results[:doctor].is_a?(Array) && results[:doctor].any?
      puts "\n⚠️  Health Issues:"
      results[:doctor].each { |issue| puts "   - #{issue}" }
    else
      puts '✅ Health Check'
    end

    puts '=' * 60

    unless check_only
      puts "\n💡 Session log: #{@sop_log}"
      puts '💾 Rollback available: ./Scripts/SaneMaster.rb sop --rollback'
    end

    puts "\n🎯 Ready to work!"
  end

  # =============================================================================
  # Version Checking - Fetch latest versions from Homebrew/GitHub
  # =============================================================================

  VERSION_CACHE_FILE = File.expand_path('~/.sanemaster/versions_cache.json')
  VERSION_CACHE_MAX_AGE = 7 * 24 * 60 * 60 # 7 days in seconds

  TOOL_SOURCES = {
    'swiftlint' => { type: :homebrew, formula: 'swiftlint' },
    'xcodegen' => { type: :homebrew, formula: 'xcodegen' },
    'periphery' => { type: :homebrew, formula: 'periphery' },
    'mockolo' => { type: :github, repo: 'uber/mockolo' },
    'lefthook' => { type: :homebrew, formula: 'lefthook' },
    'fastlane' => { type: :rubygems, gem: 'fastlane' },
    'ruby' => { type: :homebrew, formula: 'ruby' }
  }.freeze

  def check_latest_versions(args)
    puts '🔍 --- [ SANEMASTER VERSION CHECK ] ---'
    force_refresh = args.include?('--refresh') || args.include?('-f')

    # Load or fetch version cache
    cache = load_version_cache(force_refresh: force_refresh)

    if cache[:fetched_at]
      age_days = ((Time.now - Time.parse(cache[:fetched_at])) / 86_400).round(1)
      puts "📅 Cache age: #{age_days} days #{'(refreshed)' if force_refresh}"
      puts ''
    end

    # Compare installed vs latest
    puts 'Tool            Installed    Latest       Status'
    puts '-' * 55

    all_current = true
    TOOL_SOURCES.each_key do |tool|
      installed = get_installed_version(tool)
      latest = cache[:versions][tool] || 'unknown'

      status = if installed == 'not installed'
                 all_current = false
                 '❌ missing'
               elsif latest == 'unknown'
                 '❓ unknown'
               elsif Gem::Version.new(installed.gsub(/[^\d.]/, '')) >= Gem::Version.new(latest.gsub(/[^\d.]/, ''))
                 '✅ current'
               else
                 all_current = false
                 '⬆️  update available'
               end

      puts format('%-15<tool>s %-12<installed>s %-12<latest>s %<status>s',
                  tool: tool, installed: installed, latest: latest, status: status)
    end

    puts ''
    if all_current
      puts '✅ All tools are up to date!'
    else
      puts '💡 Run `brew upgrade <tool>` or `./Scripts/SaneMaster.rb bootstrap` to update'
    end

    puts "\n🔄 To refresh cache: ./Scripts/SaneMaster.rb versions --refresh"
  end

  def load_version_cache(force_refresh: false)
    ensure_sop_dirs

    # Check if cache exists and is fresh
    if !force_refresh && File.exist?(VERSION_CACHE_FILE)
      begin
        cache = JSON.parse(File.read(VERSION_CACHE_FILE), symbolize_names: true)
        cache_age = Time.now - Time.parse(cache[:fetched_at])
        return cache if cache_age < VERSION_CACHE_MAX_AGE
      rescue StandardError
        # Cache corrupted, will refresh
      end
    end

    # Fetch fresh versions
    puts '🌐 Fetching latest versions from package managers...'
    versions = {}

    TOOL_SOURCES.each do |tool, config|
      print "   #{tool}... "
      version = fetch_latest_version(config)
      versions[tool] = version
      puts version
    end

    cache = {
      fetched_at: Time.now.iso8601,
      versions: versions
    }

    File.write(VERSION_CACHE_FILE, JSON.pretty_generate(cache))
    puts ''
    cache
  end

  def fetch_latest_version(config)
    case config[:type]
    when :homebrew
      # Homebrew only serves stable versions by default
      output = `brew info #{config[:formula]} 2>/dev/null`.lines.first
      # Match patterns like "==> swiftlint: stable 0.62.2" or "swiftlint: 0.62.2"
      version = output&.match(/stable ([\d.]+)/)&.[](1) ||
                output&.match(/#{config[:formula]}[:\s]+([\d.]+)/)&.[](1)
      # Double-check it's not a beta/rc version
      return 'unknown' if version&.match?(/alpha|beta|rc|pre/i)

      version || 'unknown'
    when :github
      # Fetch releases and find latest stable (not prerelease)
      output = `curl -s "https://api.github.com/repos/#{config[:repo]}/releases" 2>/dev/null`
      begin
        releases = JSON.parse(output)
        # Find first non-prerelease, non-draft release
        stable = releases.find { |r| !r['prerelease'] && !r['draft'] }
        version = stable&.dig('tag_name')&.gsub(/^v/, '')
        # Skip if version contains alpha/beta/rc
        return 'unknown' if version&.match?(/alpha|beta|rc|pre/i)

        version || 'unknown'
      rescue StandardError
        'unknown'
      end
    when :rubygems
      # RubyGems returns stable versions by default
      output = `gem search ^#{config[:gem]}$ --remote 2>/dev/null`
      version = output&.match(/#{config[:gem]} \(([\d.]+)\)/)&.[](1)
      return 'unknown' if version&.match?(/alpha|beta|rc|pre/i)

      version || 'unknown'
    else
      'unknown'
    end
  rescue StandardError
    'unknown'
  end

  def get_installed_version(tool)
    case tool
    when 'swiftlint'
      `swiftlint --version 2>/dev/null`.strip.split.first || 'not installed'
    when 'xcodegen'
      output = `xcodegen --version 2>/dev/null`
      output.match(/Version: ([\d.]+)/)&.[](1) || 'not installed'
    when 'periphery'
      `periphery version 2>/dev/null`.strip || 'not installed'
    when 'mockolo'
      `mockolo --version 2>/dev/null`.strip || 'not installed'
    when 'lefthook'
      output = `lefthook --version 2>/dev/null`
      output.match(/lefthook version ([\d.]+)/)&.[](1) || 'not installed'
    when 'fastlane'
      output = `#{HOMEBREW_BUNDLE} exec fastlane --version 2>/dev/null`
      output.match(/fastlane ([\d.]+)/)&.[](1) || 'not installed'
    when 'ruby'
      output = `#{HOMEBREW_RUBY} --version 2>/dev/null`
      output.match(/ruby ([\d.]+)/)&.[](1) || 'not installed'
    else
      'unknown'
    end
  rescue StandardError
    'not installed'
  end

  # =============================================================================
  # CI Parity Check - Compare local environment with CI configuration
  # =============================================================================

  def check_ci_parity
    puts '🔄 --- [ SANEMASTER CI PARITY CHECK ] ---'
    puts 'Comparing local environment with CI configuration...'
    puts ''

    issues = []

    # Check GitHub Actions workflow
    gh_workflow = Dir.glob('.github/workflows/*.yml').first
    if gh_workflow
      puts "📄 Found: #{gh_workflow}"
      workflow = File.read(gh_workflow)

      # Extract Xcode version from workflow
      xcode_match = workflow.match(/xcode-version:\s*['"]?([\d.]+)['"]?/i) ||
                    workflow.match(/DEVELOPER_DIR.*Xcode[_-]?([\d.]+)/i)
      if xcode_match
        ci_xcode = xcode_match[1]
        local_xcode = `xcodebuild -version 2>/dev/null`.lines.first&.match(/Xcode ([\d.]+)/)&.[](1)
        if local_xcode && ci_xcode != local_xcode
          issues << "Xcode: CI uses #{ci_xcode}, local is #{local_xcode}"
        else
          puts "   ✅ Xcode version matches: #{local_xcode}"
        end
      end

      # Check for Ruby version
      ruby_match = workflow.match(/ruby-version:\s*['"]?([\d.]+)['"]?/i)
      if ruby_match
        ci_ruby = ruby_match[1]
        local_ruby = `#{HOMEBREW_RUBY} --version 2>/dev/null`.match(/ruby ([\d.]+)/)&.[](1)
        if local_ruby && !local_ruby.start_with?(ci_ruby)
          issues << "Ruby: CI uses #{ci_ruby}, local is #{local_ruby}"
        else
          puts "   ✅ Ruby version compatible: #{local_ruby}"
        end
      end
    else
      puts '⚠️  No GitHub Actions workflow found'
    end

    # Check Fastlane Fastfile
    fastfile = 'fastlane/Fastfile'
    if File.exist?(fastfile)
      puts "\n📄 Found: #{fastfile}"
      content = File.read(fastfile)

      # Check for specific version pins
      puts '   ℹ️  Fastfile uses xcversion for Xcode management' if content.include?('xcversion')
    end

    # Check .xcode-version file
    xcode_version_file = '.xcode-version'
    if File.exist?(xcode_version_file)
      pinned = File.read(xcode_version_file).strip
      local = `xcodebuild -version 2>/dev/null`.lines.first&.match(/Xcode ([\d.]+)/)&.[](1)
      if local == pinned
        puts "\n✅ .xcode-version matches local: #{local}"
      else
        issues << ".xcode-version pins #{pinned}, local is #{local}"
      end
    end

    # Check Gemfile.lock for version mismatches
    if File.exist?('Gemfile.lock')
      puts "\n📄 Checking Gemfile.lock..."
      lock_content = File.read('Gemfile.lock')

      # Check bundled with version
      bundler_match = lock_content.match(/BUNDLED WITH\n\s+([\d.]+)/)
      if bundler_match
        ci_bundler = bundler_match[1]
        local_bundler = `#{HOMEBREW_BUNDLE} --version 2>/dev/null`.match(/Bundler version ([\d.]+)/)&.[](1)
        if local_bundler && Gem::Version.new(local_bundler) < Gem::Version.new(ci_bundler)
          issues << "Bundler: lock requires #{ci_bundler}, local is #{local_bundler}"
        else
          puts "   ✅ Bundler version compatible: #{local_bundler}"
        end
      end
    end

    # Summary
    puts "\n#{'=' * 50}"
    if issues.empty?
      puts '✅ CI PARITY: Local environment matches CI configuration'
    else
      puts '⚠️  CI PARITY ISSUES FOUND:'
      issues.each { |issue| puts "   - #{issue}" }
      puts "\n💡 Fix these to avoid CI failures"
    end
    puts '=' * 50
  end

  # =============================================================================
  # Dependency Graph - Visualize project dependencies
  # =============================================================================

  def show_dependency_graph(args)
    puts '📊 --- [ SANEMASTER DEPENDENCY GRAPH ] ---'

    output_format = args.include?('--dot') ? :dot : :ascii

    deps = {
      swift_packages: scan_swift_packages,
      ruby_gems: scan_ruby_gems,
      homebrew: scan_homebrew_deps,
      frameworks: scan_frameworks
    }

    if output_format == :dot
      generate_dot_graph(deps)
    else
      print_ascii_graph(deps)
    end
  end

  def scan_swift_packages
    package_file = 'SaneVideo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    package_file = 'Package.resolved' unless File.exist?(package_file)

    return [] unless File.exist?(package_file)

    begin
      data = JSON.parse(File.read(package_file))
      pins = data['pins'] || data.dig('object', 'pins') || []
      pins.map do |pin|
        {
          name: pin['identity'] || pin['package'],
          version: pin.dig('state', 'version') || pin.dig('state', 'revision')&.[](0..6) || 'branch',
          url: pin['location'] || pin['repositoryURL']
        }
      end
    rescue StandardError
      []
    end
  end

  def scan_ruby_gems
    return [] unless File.exist?('Gemfile.lock')

    gems = []
    in_specs = false

    File.readlines('Gemfile.lock').each do |line|
      stripped = line.strip
      if stripped == 'specs:'
        in_specs = true
      elsif in_specs && line.match(/^\s{4}(\S+)\s+\(([\d.]+)\)/)
        gems << { name: ::Regexp.last_match(1), version: ::Regexp.last_match(2) }
      elsif stripped == 'GEM' || stripped.empty? || line.start_with?('PLATFORMS')
        in_specs = false
      end
    end

    gems.first(15) # Top 15 gems
  end

  def scan_homebrew_deps
    TOOL_SOURCES.keys.map do |tool|
      version = get_installed_version(tool)
      { name: tool, version: version } if version != 'not installed'
    end.compact
  end

  def scan_frameworks
    # Scan for framework imports in Swift files
    frameworks = Set.new
    Dir.glob('SaneVideo/**/*.swift').each do |file|
      File.readlines(file).each do |line|
        if line.match(/^import\s+(\w+)/)
          fw = ::Regexp.last_match(1)
          frameworks << fw unless %w[Foundation SwiftUI Combine].include?(fw)
        end
      end
    rescue StandardError
      next
    end
    frameworks.to_a.sort.map { |f| { name: f, version: 'system' } }
  end

  def print_ascii_graph(deps)
    puts ''
    puts '┌─────────────────────────────────────────────────────────┐'
    puts '│                    SaneVideo                            │'
    puts '└─────────────────────────────────────────────────────────┘'
    puts '                           │'

    # Swift Packages
    if deps[:swift_packages].any?
      puts '          ┌────────────────┴────────────────┐'
      puts '          │        Swift Packages           │'
      puts '          └─────────────────────────────────┘'
      deps[:swift_packages].each do |pkg|
        puts "                    ├── #{pkg[:name]} (#{pkg[:version]})"
      end
      puts ''
    end

    # Ruby Gems
    if deps[:ruby_gems].any?
      puts '          ┌─────────────────────────────────┐'
      puts '          │          Ruby Gems              │'
      puts '          └─────────────────────────────────┘'
      deps[:ruby_gems].first(10).each do |gem|
        puts "                    ├── #{gem[:name]} (#{gem[:version]})"
      end
      puts "                    └── ... and #{deps[:ruby_gems].count - 10} more" if deps[:ruby_gems].count > 10
      puts ''
    end

    # Homebrew Tools
    if deps[:homebrew].any?
      puts '          ┌─────────────────────────────────┐'
      puts '          │        Homebrew Tools           │'
      puts '          └─────────────────────────────────┘'
      deps[:homebrew].each do |tool|
        puts "                    ├── #{tool[:name]} (#{tool[:version]})"
      end
      puts ''
    end

    # Apple Frameworks
    if deps[:frameworks].any?
      puts '          ┌─────────────────────────────────┐'
      puts '          │       Apple Frameworks          │'
      puts '          └─────────────────────────────────┘'
      deps[:frameworks].first(15).each do |fw|
        puts "                    ├── #{fw[:name]}"
      end
      puts "                    └── ... and #{deps[:frameworks].count - 15} more" if deps[:frameworks].count > 15
    end

    puts ''
    puts "📊 Total: #{deps[:swift_packages].count} Swift packages, #{deps[:ruby_gems].count} gems, " \
         "#{deps[:homebrew].count} tools, #{deps[:frameworks].count} frameworks"
  end

  def generate_dot_graph(deps)
    dot_file = 'dependencies.dot'
    File.open(dot_file, 'w') do |f|
      f.puts 'digraph Dependencies {'
      f.puts '  rankdir=TB;'
      f.puts '  node [shape=box];'
      f.puts ''
      f.puts '  SaneVideo [style=filled, fillcolor=lightblue];'
      f.puts ''

      deps[:swift_packages].each do |pkg|
        f.puts "  \"#{pkg[:name]}\" [label=\"#{pkg[:name]}\\n#{pkg[:version]}\"];"
        f.puts "  SaneVideo -> \"#{pkg[:name]}\";"
      end

      deps[:homebrew].each do |tool|
        f.puts "  \"#{tool[:name]}\" [label=\"#{tool[:name]}\\n#{tool[:version]}\", style=filled, fillcolor=lightyellow];"
        f.puts "  SaneVideo -> \"#{tool[:name]}\" [style=dashed];"
      end

      f.puts '}'
    end

    puts "✅ Generated: #{dot_file}"
    puts '💡 View with: dot -Tpng dependencies.dot -o dependencies.png && open dependencies.png'
    puts '   Or online: https://dreampuf.github.io/GraphvizOnline/'
  end

  # =============================================================================
  # Project Templates - Save and apply project configurations
  # =============================================================================

  TEMPLATE_DIR = File.expand_path('~/.sanemaster/templates')

  def manage_templates(args)
    ensure_template_dir

    subcommand = args.shift || 'list'

    case subcommand
    when 'save'
      save_template(args.first || 'default')
    when 'apply'
      apply_template(args.first || 'default')
    when 'list'
      list_templates
    when 'delete'
      delete_template(args.first)
    else
      puts "Unknown template command: #{subcommand}"
      puts 'Usage: template [save|apply|list|delete] [name]'
    end
  end

  def ensure_template_dir
    FileUtils.mkdir_p(TEMPLATE_DIR)
  end

  def save_template(name)
    puts "📦 --- [ SAVE TEMPLATE: #{name} ] ---"

    template_path = File.join(TEMPLATE_DIR, name)
    FileUtils.mkdir_p(template_path)

    # Files to include in template
    template_files = {
      'Gemfile' => 'Gemfile',
      '.ruby-version' => '.ruby-version',
      '.swiftlint.yml' => '.swiftlint.yml',
      'project.yml' => 'project.yml',
      '.mcp.json' => '.mcp.json',
      'lefthook.yml' => 'lefthook.yml',
      '.claude/settings.json' => '.claude/settings.json'
    }

    saved = []
    template_files.each do |src, dest|
      src_path = File.join(Dir.pwd, src)
      next unless File.exist?(src_path)

      dest_path = File.join(template_path, dest)
      FileUtils.mkdir_p(File.dirname(dest_path))
      FileUtils.cp(src_path, dest_path)
      saved << src
    end

    # Save metadata
    metadata = {
      name: name,
      created_at: Time.now.iso8601,
      source_project: File.basename(Dir.pwd),
      files: saved
    }
    File.write(File.join(template_path, 'metadata.json'), JSON.pretty_generate(metadata))

    puts "✅ Template saved: #{template_path}"
    puts "   Files: #{saved.join(', ')}"
    puts "\n💡 Apply to new project: ./Scripts/SaneMaster.rb template apply #{name}"
  end

  def apply_template(name)
    puts "📥 --- [ APPLY TEMPLATE: #{name} ] ---"

    template_path = File.join(TEMPLATE_DIR, name)
    unless File.exist?(template_path)
      puts "❌ Template not found: #{name}"
      list_templates
      return
    end

    metadata_file = File.join(template_path, 'metadata.json')
    if File.exist?(metadata_file)
      metadata = JSON.parse(File.read(metadata_file))
      puts "📋 Template from: #{metadata['source_project']} (#{metadata['created_at']})"
    end

    # Copy template files (skip existing unless --force)
    applied = []
    Dir.glob(File.join(template_path, '**/*')).each do |src|
      next if File.directory?(src)
      next if src.end_with?('metadata.json')

      relative = src.sub("#{template_path}/", '')
      dest = File.join(Dir.pwd, relative)

      if File.exist?(dest)
        puts "   ⚠️  Skipping (exists): #{relative}"
        next
      end

      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(src, dest)
      applied << relative
    end

    if applied.any?
      puts "\n✅ Applied files:"
      applied.each { |f| puts "   - #{f}" }
      puts "\n💡 Run ./Scripts/SaneMaster.rb bootstrap to complete setup"
    else
      puts '⚠️  No new files applied (all exist already)'
    end
  end

  def list_templates
    puts '📋 --- [ AVAILABLE TEMPLATES ] ---'

    templates = Dir.glob(File.join(TEMPLATE_DIR, '*')).select { |f| File.directory?(f) }

    if templates.empty?
      puts '   No templates saved yet.'
      puts "\n💡 Save current project as template: ./Scripts/SaneMaster.rb template save mytemplate"
      return
    end

    templates.each do |template_path|
      name = File.basename(template_path)
      metadata_file = File.join(template_path, 'metadata.json')

      if File.exist?(metadata_file)
        metadata = JSON.parse(File.read(metadata_file))
        puts "   #{name}"
        puts "      From: #{metadata['source_project']}"
        puts "      Created: #{metadata['created_at']}"
        puts "      Files: #{metadata['files']&.count || '?'}"
      else
        puts "   #{name} (no metadata)"
      end
      puts ''
    end
  end

  def delete_template(name)
    return puts '❌ Specify template name to delete' unless name

    template_path = File.join(TEMPLATE_DIR, name)
    unless File.exist?(template_path)
      puts "❌ Template not found: #{name}"
      return
    end

    FileUtils.rm_rf(template_path)
    puts "✅ Deleted template: #{name}"
  end

  def generate_test_assets
    puts '🎬 --- [ SANEMASTER TEST ASSETS ] ---'
    puts 'Generating lightweight test media...'

    assets_dir = 'Tests/Assets'
    FileUtils.mkdir_p(assets_dir)

    # Check if ffmpeg is available
    unless system('which ffmpeg > /dev/null 2>&1')
      puts '❌ ffmpeg not found. Install: brew install ffmpeg'
      return
    end

    # Generate 5-second test video (640x480, 30fps, silent)
    video_path = "#{assets_dir}/test_video.mp4"
    if File.exist?(video_path)
      puts '  ⚠️  test_video.mp4 already exists, skipping'
    else
      print '  Generating test_video.mp4 (5s, 640x480)... '
      cmd = "ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=30 -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p -y #{video_path} 2>/dev/null"
      if system(cmd)
        puts '✅'
      else
        puts '❌ Failed'
      end
    end

    # Generate silence audio (5 seconds)
    silence_path = "#{assets_dir}/test_silence.mp4"
    if File.exist?(silence_path)
      puts '  ⚠️  test_silence.mp4 already exists, skipping'
    else
      print '  Generating test_silence.mp4 (5s silence)... '
      cmd = "ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 5 -c:a aac -y #{silence_path} 2>/dev/null"
      if system(cmd)
        puts '✅'
      else
        puts '❌ Failed'
      end
    end

    puts "\n✅ Test assets ready."
  end

  # --- NEW: Test Generation Tool ---

  def generate_test_file(args)
    puts '🧪 --- [ SANEMASTER TEST GENERATOR ] ---'

    if args.empty?
      puts 'Usage: ./Scripts/SaneMaster.rb gen_test <test_name> [options]'
      puts ''
      puts 'Options:'
      puts '  --type <unit|ui>     Test type (default: unit)'
      puts '  --framework <xctest|testing>  Framework (default: testing)'
      puts '  --target <class>     Target class/service to test'
      puts '  --async              Include async/await patterns'
      puts ''
      puts 'Examples:'
      puts '  ./Scripts/SaneMaster.rb gen_test MyFeatureTests --target MyFeature'
      puts '  ./Scripts/SaneMaster.rb gen_test MyUITests --type ui --framework xctest'
      return
    end

    test_name = args.shift
    options = parse_test_options(args)

    # Determine test directory
    test_dir = options[:type] == 'ui' ? 'SaneVideoUITests' : 'SaneVideoTests'
    test_file = "#{test_dir}/#{test_name}.swift"

    if File.exist?(test_file)
      puts "⚠️  File already exists: #{test_file}"
      print 'Overwrite? (y/N): '
      return unless $stdin.gets.chomp.downcase == 'y'
    end

    # Generate test content
    content = generate_test_content(test_name, options)

    # Write file
    File.write(test_file, content)
    puts "✅ Created: #{test_file}"
    puts ''
    puts '📝 Next steps:'
    puts '  1. Review the generated test template'
    puts '  2. Add your test cases following AAA pattern (Arrange-Act-Assert)'
    puts '  3. Run: ./Scripts/SaneMaster.rb verify'
  end

  def parse_test_options(args)
    options = {
      type: 'unit',
      framework: 'testing',
      target: nil,
      async: false
    }

    args.each_with_index do |arg, i|
      case arg
      when '--type'
        options[:type] = args[i + 1] if args[i + 1]
      when '--framework'
        options[:framework] = args[i + 1] if args[i + 1]
      when '--target'
        options[:target] = args[i + 1] if args[i + 1]
      when '--async'
        options[:async] = true
      end
    end

    options
  end

  def generate_test_content(test_name, options)
    if options[:framework] == 'xctest'
      generate_xctest_content(test_name, options)
    else
      generate_testing_framework_content(test_name, options)
    end
  end

  def generate_xctest_content(test_name, options)
    target_class = options[:target] || 'TargetClass'
    async_suffix = options[:async] ? ' async throws' : ''
    await_prefix = options[:async] ? 'await ' : ''

    <<~SWIFT
      //
      //  #{test_name}.swift
      //  #{options[:type] == 'ui' ? 'SaneVideoUITests' : 'SaneVideoTests'}
      //
      //  Generated by SaneMaster.rb test generator
      //  Follow AAA pattern: Arrange-Act-Assert
      //

      import XCTest
      #{'import XCUITest' if options[:type] == 'ui'}
      #{'import AVFoundation' if options[:async]}
      @testable import SaneVideo

      @MainActor
      final class #{test_name}: XCTestCase {
      #{'    '}
          // MARK: - Test Setup
      #{'    '}
          var sut: #{target_class}!
      #{'    '}
          override func setUpWithError() throws {
              continueAfterFailure = false
      #{'        '}
              // Set test timeout to prevent hanging
              if #available(macOS 13.0, *) {
                  executionTimeAllowance = #{options[:type] == 'ui' ? '300.0' : '60.0'} // #{options[:type] == 'ui' ? '5 minutes' : '1 minute'} max per test
              }
      #{'        '}
              // Arrange: Initialize system under test
              sut = #{target_class}()
          }
      #{'    '}
          override func tearDownWithError() throws {
              // Cleanup
              sut = nil
          }
      #{'    '}
          // MARK: - Test Cases
      #{'    '}
          func testInitialState()#{async_suffix} {
              // Arrange
              // (Setup is done in setUp)
      #{'        '}
              // Act
              // Perform action
      #{'        '}
              // Assert
              XCTAssertNotNil(sut, "SUT should be initialized")
          }
      #{'    '}
          func testBasicFunctionality()#{async_suffix} {
              // Arrange
              let expectedValue = "expected"
      #{'        '}
              // Act
              #{await_prefix}let result = sut.someMethod()
      #{'        '}
              // Assert
              XCTAssertEqual(result, expectedValue, "Result should match expected value")
          }
      #{'    '}
          // MARK: - Helper Methods
      #{'    '}
          private func createTestVideo() -> URL {
              let testAsset = TestEnvironment.mockAssetURL
              if FileManager.default.fileExists(atPath: testAsset.path) {
                  return testAsset
              }
      #{'        '}
              let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
              let url = tempDir.appendingPathComponent("test_video.mp4")
              FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
              return url
          }
      }
    SWIFT
  end

  def generate_testing_framework_content(test_name, options)
    target_class = options[:target] || 'TargetClass'
    async_suffix = options[:async] ? ' async throws' : ''
    await_prefix = options[:async] ? 'await ' : ''

    <<~SWIFT
      //
      //  #{test_name}.swift
      //  #{options[:type] == 'ui' ? 'SaneVideoUITests' : 'SaneVideoTests'}
      //
      //  Generated by SaneMaster.rb test generator
      //  Follow AAA pattern: Arrange-Act-Assert
      //

      import Testing
      #{'import XCUITest' if options[:type] == 'ui'}
      #{'import AVFoundation' if options[:async]}
      @testable import SaneVideo

      @Suite("#{test_name.gsub(/([A-Z])/, ' \1').strip} Tests")
      @MainActor
      struct #{test_name} {
      #{'    '}
          // MARK: - Test Setup
      #{'    '}
          var sut: #{target_class} {
              // Arrange: Initialize system under test
              #{target_class}()
          }
      #{'    '}
          // MARK: - Test Cases
      #{'    '}
          @Test("Initial state verification")
          func initialState()#{async_suffix} {
              // Arrange
              let systemUnderTest = sut
      #{'        '}
              // Act
              // Perform action
      #{'        '}
              // Assert
              #expect(systemUnderTest != nil)
          }
      #{'    '}
          @Test("Basic functionality")
          func basicFunctionality()#{async_suffix} {
              // Arrange
              let expectedValue = "expected"
      #{'        '}
              // Act
              #{await_prefix}let result = sut.someMethod()
      #{'        '}
              // Assert
              #expect(result == expectedValue)
          }
      #{'    '}
          // MARK: - Helper Methods
      #{'    '}
          private func createTestVideo() -> URL {
              let testAsset = TestEnvironment.mockAssetURL
              if FileManager.default.fileExists(atPath: testAsset.path) {
                  return testAsset
              }
      #{'        '}
              let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
              let url = tempDir.appendingPathComponent("test_video.mp4")
              FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
              return url
          }
      }
    SWIFT
  end

  # --- Mock Generation Tool (Mockolo Integration) ---

  def generate_mocks(args)
    puts '🎭 --- [ SANEMASTER MOCK GENERATOR ] ---'

    # Check if Mockolo is installed
    unless system('which mockolo > /dev/null 2>&1')
      puts '❌ Mockolo not found.'
      puts ''
      puts 'Install Mockolo:'
      puts '  brew install mockolo'
      puts ''
      puts 'Or install from source:'
      puts '  https://github.com/uber/mockolo'
      return
    end

    if args.empty?
      puts 'Usage: ./Scripts/SaneMaster.rb gen_mock [options]'
      puts ''
      puts 'Options:'
      puts '  --target <dir>        Generate mocks for all protocols in directory'
      puts '  --protocol <name>     Generate mock for specific protocol'
      puts '  --output <dir>        Output directory (default: SaneVideoTests/Mocks)'
      puts ''
      puts 'Examples:'
      puts '  ./Scripts/SaneMaster.rb gen_mock --target Services/Camera'
      puts '  ./Scripts/SaneMaster.rb gen_mock --protocol CameraServiceProtocol'
      return
    end

    # Parse options
    target = nil
    protocol = nil
    output_dir = 'SaneVideoTests/Mocks'

    args.each_with_index do |arg, i|
      case arg
      when '--target'
        target = args[i + 1] if args[i + 1]
      when '--protocol'
        protocol = args[i + 1] if args[i + 1]
      when '--output'
        output_dir = args[i + 1] if args[i + 1]
      end
    end

    # Create output directory
    FileUtils.mkdir_p(output_dir)

    # Mockolo expects a file path for -d, not a directory
    output_file = File.join(output_dir, 'Mocks.swift')

    # Generate mocks
    if target
      puts "Generating mocks for target: #{target}"
      source_dir = "SaneVideo/#{target}"
      unless File.directory?(source_dir)
        puts "❌ Directory not found: #{source_dir}"
        return
      end

      # Don't use custom-imports (it adds them incorrectly), we'll add @testable manually
      cmd = "mockolo -s #{source_dir} -d #{output_file} --enable-args-history --mock-all"
      puts "Running: #{cmd}"
      if system(cmd)
        # Post-process: Fix imports and nonisolated properties
        if File.exist?(output_file)
          content = File.read(output_file)
          # Remove any malformed import lines (from custom-imports)
          content.gsub!(/^import [A-Za-z]+ [A-Za-z]+.*\n/, '')
          # rubocop:disable Layout/LineLength
          # Add @testable import after Foundation if not present
          content.gsub!(/(import Foundation\n)/, "\\1@testable import SaneVideo\n") unless content.include?('@testable import SaneVideo')
          # Fix nonisolated sampleBufferSubject for CameraServiceProtocol
          # Replace stored property with computed property that uses MainActor.assumeIsolated
          content.gsub!('private var _sampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never>!',
                        'private var _sampleBufferSubjectStorage: PassthroughSubject<CMSampleBuffer, Never>!')
          content.gsub!(/(var sampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> \{)/, 'nonisolated \\1')
          content.gsub!(/(get \{ return _sampleBufferSubject \})/,
                        "get { \n            return MainActor.assumeIsolated {\n                if _sampleBufferSubjectStorage == nil {\n                    _sampleBufferSubjectStorage = PassthroughSubject<CMSampleBuffer, Never>()\n                }\n                return _sampleBufferSubjectStorage \n            }\n        }")
          content.gsub!(/(set \{ _sampleBufferSubject = newValue \})/,
                        "set { \n            MainActor.assumeIsolated {\n                _sampleBufferSubjectStorage = newValue\n            }\n        }")
          # rubocop:enable Layout/LineLength
          File.write(output_file, content)
        end
        puts '✅ Mocks generated successfully'
      else
        puts '❌ Mock generation failed'
        return
      end

    elsif protocol
      puts "Generating mock for protocol: #{protocol}"
      # Find protocol file
      protocol_file = `find SaneVideo -name "*.swift" -exec grep -l "protocol #{protocol}" {} \\;`.strip

      if protocol_file.empty?
        puts "❌ Protocol not found: #{protocol}"
        puts '   Searched in SaneVideo/'
        return
      end

      protocol_dir = File.dirname(protocol_file)
      output_file = File.join(output_dir, 'Mocks.swift')
      cmd = "mockolo -s #{protocol_dir} -d #{output_file} --enable-args-history --mock-all -i #{protocol}"
      puts "Running: #{cmd}"
      if system(cmd)
        # Post-process: Add @testable import after last import statement
        if File.exist?(output_file)
          content = File.read(output_file)
          # rubocop:disable Metrics/BlockNesting
          unless content.include?('@testable import SaneVideo')
            content.gsub!(/(import Foundation\n)/, "\\1@testable import SaneVideo\n")
            File.write(output_file, content)
          end
          # rubocop:enable Metrics/BlockNesting
        end
        puts '✅ Mocks generated successfully'
      else
        puts '❌ Mock generation failed'
        return
      end

    else
      puts '❌ Must specify --target or --protocol'
      return
    end

    puts "\n✅ Mocks generated in: #{output_dir}"
    puts ''
    puts '📝 Next steps:'
    puts '  1. Review generated mocks'
    puts '  2. Import in your test files: import Mocks'
    puts '  3. Use in tests: let mock = MockCameraService()'
  end

  # --- XcodeGen Verification ---

  def check_xcodegen(files)
    # This is called from lefthook with staged files
    return if files.empty?

    project_path = File.expand_path('SaneVideo.xcodeproj', Dir.pwd)
    unless File.exist?(project_path)
      puts "❌ Project file not found. Run 'xcodegen generate' first."
      exit 1
    end

    begin
      require 'xcodeproj'
    rescue LoadError
      puts '⚠️  Skipping XcodeGen check (run with: bundle exec ./Scripts/SaneMaster.rb)'
      return
    end
    project = Xcodeproj::Project.open(project_path)
    project_files = Set.new

    # Get all Swift files in project (normalize paths for comparison)
    project.files.each do |file|
      next unless file.path&.end_with?('.swift')

      path = file.path
      # Add both with and without SaneVideo/ prefix for flexible matching
      project_files.add(path)
      project_files.add(path.sub(%r{^SaneVideo/}, ''))
      project_files.add("SaneVideo/#{path}") unless path.start_with?('SaneVideo/')
    end

    # Only check files that are newly added (not modified)
    missing_files = []
    files.each do |file|
      next unless file.end_with?('.swift')
      next if file.include?('Test') # Skip test files (they're auto-added)

      # Check if file is actually new (not just modified)
      is_new = `git diff --cached --diff-filter=A --name-only -- "#{file}" 2>/dev/null`.strip == file
      next unless is_new

      # Normalize path for comparison
      normalized = file.start_with?('SaneVideo/') ? file : "SaneVideo/#{file}"
      path_without_prefix = file.sub(%r{^SaneVideo/}, '')

      # Check if file exists in project (try multiple path variations)
      missing_files << file unless project_files.include?(file) || project_files.include?(normalized) || project_files.include?(path_without_prefix)
    end

    if missing_files.any?
      puts '❌ New Swift files not in Xcode project:'
      missing_files.each { |f| puts "   - #{f}" }
      puts "\n💡 Run: xcodegen generate"
      exit 1
    end

    exit 0
  end

  # --- SDK API Verification Tool ---

  def verify_api(args)
    if args.empty?
      puts 'Usage: ./Scripts/SaneMaster.rb verify_api <APIName> [Framework]'
      puts ''
      puts 'Examples:'
      puts '  ./Scripts/SaneMaster.rb verify_api faceCaptureQuality Vision'
      puts '  ./Scripts/SaneMaster.rb verify_api SCContentSharingPicker ScreenCaptureKit'
      return
    end

    api_name = args[0]
    framework = args[1] || 'auto'

    puts '🔍 --- [ SDK API VERIFICATION ] ---'
    puts "Searching for: #{api_name}"
    puts "Framework: #{framework == 'auto' ? 'auto-detect' : framework}"
    puts ''

    # Find SDK path
    sdk_base = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs'
    sdks = Dir.glob("#{sdk_base}/MacOSX*.sdk").sort.reverse

    if sdks.empty?
      puts '❌ No macOS SDK found. Is Xcode installed?'
      return
    end

    # Use latest SDK
    sdk_path = sdks.first
    sdk_version = File.basename(sdk_path).gsub('MacOSX', '').gsub('.sdk', '')
    puts "📦 Using SDK: #{sdk_version}"
    puts ''

    # If framework specified, search there; otherwise search common frameworks
    frameworks_to_search = if framework == 'auto'
                             %w[Vision AVFoundation ScreenCaptureKit Foundation AppKit SwiftUI CoreMedia]
                           else
                             [framework]
                           end

    found = false
    frameworks_to_search.each do |fw|
      framework_path = "#{sdk_path}/System/Library/Frameworks/#{fw}.framework"
      next unless File.exist?(framework_path)

      # Find swiftinterface files
      swiftinterface_files = Dir.glob("#{framework_path}/**/*.swiftinterface")
      next if swiftinterface_files.empty?

      swiftinterface_files.each do |swift_file|
        result = `grep -n "#{api_name}" "#{swift_file}" 2>/dev/null`
        next if result.empty?

        found = true
        puts "✅ Found in #{fw}:"
        puts "   File: #{File.basename(swift_file)}"
        puts ''
        # Show context (5 lines before and after)
        lines = result.split("\n").first(3) # Show first 3 matches
        lines.each do |line|
          line_num = line.split(':').first
          context = `sed -n '#{[line_num.to_i - 2, 1].max},#{line_num.to_i + 5}p' "#{swift_file}" 2>/dev/null`
          puts "   Line #{line_num}:"
          context.split("\n").each do |ctx_line|
            if ctx_line.include?(api_name)
              puts "   >>> #{ctx_line.strip}"
            else
              puts "      #{ctx_line.strip}"
            end
          end
          puts ''
        end
      end
    end

    return if found

    puts "❌ API '#{api_name}' not found in SDK"
    puts ''
    puts '💡 Tips:'
    puts '   - Check spelling (case-sensitive)'
    puts '   - Try searching for partial name: ./Scripts/SaneMaster.rb verify_api "Content" ScreenCaptureKit'
    puts '   - Framework may be different - try without framework to search all'
  end

  # --- Mock Synchronization Check ---

  def verify_mocks
    puts '🎭 --- [ MOCK SYNCHRONIZATION CHECK ] ---'

    # Check if Mockolo is installed
    unless system('which mockolo > /dev/null 2>&1')
      puts '❌ Mockolo not found. Install: brew install mockolo'
      return
    end

    # Find all @mockable protocols
    puts '📂 Scanning for @mockable protocols...'
    protocol_files = `find SaneVideo -name "*.swift" -exec grep -l "@mockable" {} \\;`.strip.split("\n")

    if protocol_files.empty?
      puts '⚠️  No @mockable protocols found'
      return
    end

    puts "   Found #{protocol_files.length} protocol(s) with @mockable"
    puts ''

    # Check if mocks file exists
    mocks_file = 'SaneVideoTests/Mocks/Mocks.swift'
    unless File.exist?(mocks_file)
      puts "❌ Mocks file not found: #{mocks_file}"
      puts '   Run: ./Scripts/SaneMaster.rb gen_mock --target Core/Protocols'
      return
    end

    # Generate temp mocks and compare
    puts '🔄 Generating temporary mocks for comparison...'
    temp_dir = Dir.mktmpdir
    temp_mocks = File.join(temp_dir, 'Mocks.swift')

    protocol_dir = 'SaneVideo/Core/Protocols'
    cmd = "mockolo -s #{protocol_dir} -d #{temp_mocks} --enable-args-history --mock-all 2>/dev/null"
    unless system(cmd)
      puts '❌ Failed to generate temporary mocks'
      FileUtils.rm_rf(temp_dir)
      return
    end

    # Post-process temp mocks (same as gen_mock)
    if File.exist?(temp_mocks)
      content = File.read(temp_mocks)
      content.gsub!(/^import [A-Za-z]+ [A-Za-z]+.*\n/, '')
      content.gsub!(/(import Foundation\n)/, "\\1@testable import SaneVideo\n") unless content.include?('@testable import SaneVideo')
      File.write(temp_mocks, content)
    end

    # Compare (simple line count and key protocol names)
    existing_content = File.read(mocks_file)
    temp_content = File.read(temp_mocks)

    # Extract protocol names from both
    existing_protocols = existing_content.scan(/class (\w+ProtocolMock)/).flatten
    temp_protocols = temp_content.scan(/class (\w+ProtocolMock)/).flatten

    missing = temp_protocols - existing_protocols
    extra = existing_protocols - temp_protocols

    FileUtils.rm_rf(temp_dir)

    if missing.empty? && extra.empty?
      puts '✅ Mocks are synchronized with protocols'
    else
      puts '⚠️  Mocks may be out of sync:'
      puts "   Missing mocks: #{missing.join(', ')}" if missing.any?
      puts "   Extra mocks (may be intentional): #{extra.join(', ')}" if extra.any?
      puts ''
      puts '💡 Regenerate mocks: ./Scripts/SaneMaster.rb gen_mock --target Core/Protocols'
    end
  end

  # --- Protocol Change Detection ---

  def check_protocol_changes(files)
    # This is called from lefthook with staged files
    return if files.empty?

    protocol_files = files.select do |file|
      file.include?('Protocol') && file.end_with?('.swift') && File.exist?(file)
    end

    return if protocol_files.empty?

    # Check if any protocol files contain @mockable
    changed_mockable = []
    protocol_files.each do |file|
      content = File.read(file)
      changed_mockable << file if content.include?('@mockable') || content.include?('protocol')
    end

    return unless changed_mockable.any?

    puts "\n⚠️  Protocol files with @mockable were modified:"
    changed_mockable.each { |f| puts "   - #{f}" }
    puts "\n💡 Remember to regenerate mocks:"
    puts '   ./Scripts/SaneMaster.rb gen_mock --target Core/Protocols'
    puts '   Or verify mocks are in sync:'
    puts '   ./Scripts/SaneMaster.rb verify_mocks'
    puts "\n   (This is a reminder - commit will proceed)"
  end

  # --- Documentation Sync Check ---

  # rubocop:disable Naming/PredicateMethod -- This is an action, not a predicate
  def verify_documentation_sync
    puts '📚 --- [ DOCUMENTATION SYNC CHECK ] ---'

    issues = []

    # Check if DEVELOPMENT.md mentions all SaneMaster commands
    dev_doc = File.read('DEVELOPMENT.md')
    help_output = `./Scripts/SaneMaster.rb 2>&1`

    # Extract commands from help
    commands_in_help = help_output.scan(/^\s+(\w+)/).flatten.uniq.reject { |c| ['Examples:', 'Commands:'].include?(c) }

    # Check if each command is documented
    commands_in_help.each do |cmd|
      # Skip internal/helper commands
      next if %w[console check_xcodegen check_protocol_changes].include?(cmd)

      issues << "Command '#{cmd}' exists in SaneMaster but not documented in DEVELOPMENT.md" unless dev_doc.include?(cmd) || dev_doc.include?("`#{cmd}`")
    end

    # Check for outdated command descriptions
    # Verify command mentions --ui flag
    issues << "DEVELOPMENT.md doesn't mention --ui flag for verify command" unless dev_doc.include?('verify --ui') || dev_doc.include?('--ui')

    # Check if verify_api is documented
    unless dev_doc.include?('verify_api') || dev_doc.include?('SDK API verification')
      issues << 'SDK API verification tool (verify_api) not documented in DEVELOPMENT.md'
    end

    # Check if verify_mocks is documented
    unless dev_doc.include?('verify_mocks') || dev_doc.include?('mock synchronization')
      issues << 'Mock synchronization check (verify_mocks) not documented in DEVELOPMENT.md'
    end

    if issues.empty?
      puts '✅ Documentation is in sync with tools'
    else
      puts '⚠️  Documentation drift detected:'
      issues.each { |issue| puts "   - #{issue}" }
      puts "\n💡 Update DEVELOPMENT.md to reflect current tool capabilities"
    end

    issues.any?
  end
  # rubocop:enable Naming/PredicateMethod

  # --- Existing methods continue below ---

  def print_help
    puts <<~HELP
      SaneMaster - Professional Automation Suite for SaneVideo

      Commands:
        verify [--ui] [--clean] [--skip-test-validation]
          Build and run tests (unit tests by default, --ui for UI tests)
          --skip-test-validation: Skip test reference validation

        validate_test_references (or validate-tests)
          Validate that all UI test references match actual UI code
          Prevents tests from referencing non-existent UI elements

        diagnose [path] [--dump]
          Run intelligent heuristics on a .xcresult bundle

        doctor
          Check environment, mock assets, and permissions

        audit
          Scan project for missing accessibility identifiers

        clean [--nuclear]
          Safely wipe build cache and test states

        reset
          Wipe TCC privacy permissions (Camera, Mic, Screen)

        setup
          Install missing gems and system dependencies

        lint
          Run SwiftLint and auto-fix common issues

        quality
          Generate Ruby quality reports (HTML)

        gen_test [options]
          Generate test file from template

        gen_mock
          Generate mocks using Mockolo

        verify_api <APIName> [Framework]
          Verify API exists in SDK

        verify_mocks
          Verify all mocks are up to date

        verify_mcps
          Verify all SOP-required MCP servers are configured

        check_xcodegen [files]
          Check if new Swift files are in Xcode project

        check_protocol_changes [files]
          Check for protocol changes that might break mocks

        check_docs
          Check documentation is in sync with code

        dead_code (or find_dead_code)
          Scan for unused code using Periphery

        check_deprecations (or deprecations)
          Scan for deprecated API usage and warnings

        swift6_check (or swift6, concurrency_check)
          Verify Swift 6 concurrency compliance
          Checks for proper actor isolation, Sendable, @MainActor usage

        test_suite (or suite) [--quick] [--full] [--ci]
          Run comprehensive validation suite (all static analysis tools)
          --quick: Fast checks only (lint, test references, xcodegen)
          --full: All checks including slow ones (dead code, deprecations)
          --ci: CI-optimized (excludes slow checks, includes build)

        crash_report (or crashes) [--details] [--recent]
          Analyze crash reports for patterns and root causes
          --details (-d): Show individual crash details
          --recent (-r): Last 24 hours only

        logs [--tail N] [--follow]
          Show SaneVideo application logs
          --tail N: Show last N lines (default: 50)
          --follow (-f): Follow log file (like tail -f)
          Log location: ~/Movies/SaneVideo/SaneVideo_Debug.log

        test_mode (or tm)
          Enter interactive debugging workflow:
          1. Kill existing app instances
          2. Show recent screenshots (Screenshots/)
          3. Show recent crash reports
          4. Build the app
          5. Launch the app
          6. Show log file status
          Use when user says "test mode" to prepare clean debugging environment

        bootstrap (or preflight, env)
          Full environment bootstrap (runs automatically on session start):
          1. Snapshot current config (for rollback)
          2. Check/update Ruby environment
          3. Update bundle dependencies
          4. Update Homebrew tools (SwiftLint, XcodeGen, etc.)
          5. Verify Claude plugins & MCP servers
          6. Run doctor health check
          7. Report summary
          Use at start of every session to ensure environment is ready.
          --check-only: Report status without making changes
          --rollback: Restore previous configuration snapshot

        versions (or version_check)
          Check installed tool versions against latest stable releases.
          Fetches from Homebrew, GitHub, and RubyGems (cached for 7 days).
          Only shows stable releases (excludes alpha/beta/rc versions).
          --refresh (-f): Force refresh the version cache

        ci_parity (or ci_check)
          Compare local environment with CI configuration.
          Checks GitHub Actions workflow, Gemfile.lock, .xcode-version.
          Warns about version mismatches that could cause CI failures.

        deps (or dependencies)
          Show project dependency graph (Swift packages, gems, frameworks).
          --dot: Output GraphViz DOT format for visualization

        template [save|apply|list|delete] [name]
          Manage project configuration templates.
          save <name>   - Save current project config as template
          apply <name>  - Apply template to current directory
          list          - Show available templates
          delete <name> - Remove a template

        check_binary
          Audit binary for security issues

        restore
          Fix common Xcode/Launch Services issues

        gen_assets
          Generate test video assets

        console
          Open Pry console for debugging
    HELP
  end

  # ... existing methods continue ...

  def doctor
    puts '🏥 --- [ SANEMASTER DOCTOR ] ---'

    # Check disk space
    puts "\n💾 Disk Space:"
    disk_info = `df -h . 2>/dev/null`.lines.last&.split || []
    if disk_info.length >= 4
      available = disk_info[3]
      puts "  ✅ Available: #{available}"
      puts '  ⚠️  Low disk space! Export/build may fail' if available.include?('G') && available.to_f < 10
    end

    # Check test assets (enhanced)
    puts "\n📦 Test Assets:"
    assets_dir = 'Tests/Assets'
    test_asset_name = ENV['TEST_ASSET_NAME'] || 'test_video.mp4'
    test_video = File.join(assets_dir, test_asset_name)

    if File.exist?(test_video)
      size = File.size(test_video) / 1024 / 1024.0
      size_str = size >= 1 ? "#{size.round(1)}MB" : "#{(size * 1024).round}KB"
      puts "  ✅ #{test_asset_name} exists (#{size_str})"
    else
      puts "  ⚠️  #{test_asset_name} missing"
      puts "     Expected at: #{test_video}"
      puts '     Run: ./Scripts/SaneMaster.rb gen_assets'
      puts '     Or set TEST_ASSET_NAME env var for different file'
    end

    # Check for other common test assets
    common_assets = %w[test_video.mp4 test_video.mov test_video.m4v test_silence.mp4]
    found_assets = common_assets.select { |a| File.exist?(File.join(assets_dir, a)) }
    puts "  📋 Also found: #{found_assets.join(', ')}" if found_assets.any?

    # Check XcodeGen sync
    puts "\n📁 XcodeGen Sync:"
    project_path = 'SaneVideo.xcodeproj/project.pbxproj'
    if File.exist?(project_path)
      puts '  ✅ Project file exists'
      # Quick check: count Swift files in project vs on disk
      begin
        require 'xcodeproj'
        project = Xcodeproj::Project.open('SaneVideo.xcodeproj')
        project_swift_count = project.files.count { |f| f.path&.end_with?('.swift') }
        disk_swift_count = `find . -name "*.swift" -not -path "*/.*" -not -path "*/build/*" -not -path "*/vendor/*" | wc -l`.strip.to_i
        if (project_swift_count - disk_swift_count).abs > 15 # Allow variance for SPM/Mocks
          puts "  ⚠️  File count mismatch (project: #{project_swift_count}, disk: ~#{disk_swift_count})"
          puts '     Run: xcodegen generate'
        else
          puts "  ✅ Project appears in sync (#{project_swift_count} Swift files)"
        end
      rescue LoadError
        puts '  ⚠️  Skipping sync check (run with: bundle exec ./Scripts/SaneMaster.rb doctor)'
      rescue StandardError => e
        puts "  ⚠️  Could not verify sync: #{e.message}"
      end
    else
      puts '  ❌ Project file missing. Run: xcodegen generate'
    end

    # Check permissions
    puts "\n🔐 Permissions:"
    check_permission_status

    # Check Mockolo
    puts "\n🎭 Mock Generation:"
    if system('which mockolo > /dev/null 2>&1')
      version = `mockolo --version 2>&1`.strip
      puts "  ✅ Mockolo installed (#{version})"
    else
      puts '  ⚠️  Mockolo not found. Install: brew install mockolo'
    end

    # Check Xcode
    puts "\n🛠️  Xcode:"
    xcode_version = `xcodebuild -version 2>&1`.strip
    if xcode_version.include?('Xcode')
      puts "  ✅ #{xcode_version}"
    else
      puts '  ❌ Xcode not found'
    end

    # Check SwiftLint
    puts "\n🎨 Code Quality Tools:"
    if system('which swiftlint > /dev/null 2>&1')
      version = `swiftlint version 2>&1`.strip
      puts "  ✅ SwiftLint #{version}"
    else
      puts '  ⚠️  SwiftLint not found. Install: brew install swiftlint'
    end

    # Check for stuck processes
    puts "\n🔄 Stuck Processes:"
    stuck = `pgrep -f 'xcodebuild test|xctest|testmanagerd' 2>/dev/null`.strip
    if stuck.empty?
      puts '  ✅ No stuck test processes'
    else
      puts "  ⚠️  Found stuck processes: #{stuck.split.join(', ')}"
      puts '     Run: killall -9 xcodebuild xctest'
    end

    # Check DerivedData size
    puts "\n📁 DerivedData:"
    dd_path = File.expand_path('~/Library/Developer/Xcode/DerivedData/SaneVideo-*')
    dd_dirs = Dir.glob(dd_path)
    if dd_dirs.any?
      total_size = dd_dirs.map { |d| `du -sh "#{d}" 2>/dev/null`.split.first }.join(', ')
      puts "  📦 Size: #{total_size}"
      puts '     Clean with: ./Scripts/SaneMaster.rb clean --nuclear'
    else
      puts '  ✅ No DerivedData cache'
    end

    puts "\n✅ Doctor check complete."
  end

  def test_targets_disabled?
    # Check if test targets are commented out in project.yml
    project_yml = File.join(Dir.pwd, 'project.yml')
    return false unless File.exist?(project_yml)

    content = File.read(project_yml)
    # Check if test targets are commented out
    content.include?('# Temporarily disabled test targets') ||
      (content.include?('# targets:') && content.include?('#   - SaneVideoTests'))
  end

  def verify(args)
    # Check if tests are disabled due to SwiftUICore linker error
    if test_targets_disabled?
      puts '⚠️  Test targets are temporarily disabled due to SwiftUICore linker error (Xcode 16/macOS 26.2 bug)'
      puts '📝 Test files are preserved - they will be re-enabled when Xcode is updated'
      puts '🔧 To re-enable: Uncomment test targets in project.yml and run xcodegen generate'
      puts ''
      puts 'Building main app only (tests skipped)...'
      puts ''

      # Just build the app, don't run tests
      clean_first = args.include?('--clean')
      if clean_first
        puts '🧹 Cleaning before build...'
        clean([])
      end

      puts '🔨 Building SaneVideo app...'
      result = system("xcodebuild -project SaneVideo.xcodeproj -scheme SaneVideo -destination 'platform=macOS,arch=arm64' build")
      puts ''
      if result
        puts '✅ Build succeeded (tests disabled)'
      else
        puts '❌ Build failed'
        exit 1
      end
      return
    end

    clean_first = args.include?('--clean')
    include_ui = args.include?('--ui')
    timeout = args.include?('--timeout') ? args[args.index('--timeout') + 1].to_i : 180 # 3 min default (prevents stuck tests)

    if clean_first
      puts '🧹 Cleaning before verify...'
      clean([])
    end

    puts '🔨 --- [ SANEMASTER VERIFY ] ---'
    puts 'Building and running tests with progress monitoring...'
    puts "⏱️  Timeout: #{timeout}s | Auto-handling permissions: ✅"
    if include_ui
      puts '📱 Including UI tests (use --ui flag)'
    else
      puts '⚡ Unit tests only (use --ui to include UI tests)'
    end
    puts ''

    # Grant permissions upfront to avoid dialogs
    permission_monitor_pid = grant_test_permissions

    # Validate test references before running tests
    validate_test_references unless args.include?('--skip-test-validation')

    begin
      # Run tests with real-time progress monitoring
      result = run_tests_with_progress(timeout_seconds: timeout, include_ui: include_ui)

      if result[:success]
        puts "\n✅ Tests passed! (#{result[:tests_run]} tests, #{result[:duration]}s)"
      else
        puts "\n❌ Tests failed. Running diagnostics..."
        puts "⚠️  Test run timed out after #{timeout}s" if result[:timeout]
        diagnose(nil, dump: true)
      end
    ensure
      # ALWAYS cleanup processes when done
      cleanup_test_processes(permission_monitor_pid)
    end
  end

  def grant_test_permissions
    print '🔐 Granting test permissions... '
    # Use existing grant_permissions.applescript (more comprehensive)
    # Also reset via tccutil for reliability
    system('tccutil reset Camera com.sanevideo.SaneVideo 2>/dev/null')
    system('tccutil reset Microphone com.sanevideo.SaneVideo 2>/dev/null')
    system('tccutil reset ScreenRecording com.sanevideo.SaneVideo 2>/dev/null')

    # Start permission monitor in background and track PID for cleanup
    permission_pid = nil
    script_path = File.join(__dir__, 'grant_permissions.applescript')
    if File.exist?(script_path)
      # Start in background and capture PID using Process.spawn
      permission_pid = Process.spawn("osascript '#{script_path}' SaneVideo > /dev/null 2>&1")
      Process.detach(permission_pid) # Detach so it doesn't become zombie
    end

    puts '✅'
    permission_pid
  end

  def cleanup_test_processes(permission_monitor_pid = nil)
    print '🧹 Cleaning up test processes... '

    # Kill permission monitor if we started it
    if permission_monitor_pid
      begin
        Process.kill('TERM', permission_monitor_pid) if permission_monitor_pid.positive?
      rescue Errno::ESRCH, Errno::EPERM
        # Process already dead or we don't have permission, that's fine
      end
    end

    # Kill any remaining osascript processes for grant_permissions
    system("pkill -f 'grant_permissions.applescript' 2>/dev/null")

    # Kill any xcodebuild test processes
    system("pkill -f 'xcodebuild test' 2>/dev/null")

    # Kill any SaneVideo test processes
    system("pkill -f 'SaneVideo.*test' 2>/dev/null")

    # Kill any remaining xcodebuild processes
    system('pkill -9 xcodebuild 2>/dev/null')

    # Give it a moment to clean up
    sleep(0.5)

    # Final check - kill any stragglers
    system('killall -9 xcodebuild 2>/dev/null')
    system('killall -9 SaneVideo 2>/dev/null')

    puts '✅'
  end

  def run_tests_with_progress(timeout_seconds:, include_ui: false)
    require 'timeout'
    require 'open3'

    cmd = build_test_command(include_ui)

    # State hash to track progress across callbacks
    state = {
      start_time: Time.now,
      tests_run: 0,
      current_test: nil,
      last_update: Time.now,
      spinner_chars: ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'],
      spinner_idx: 0
    }

    result = execute_with_logging(cmd, timeout_seconds) do |line|
      handle_progress_update(line, state)
    end

    print "\r" # Clear spinner
    cleanup_test_processes # Ensure clean state

    {
      success: result[:success],
      tests_run: state[:tests_run],
      duration: (Time.now - state[:start_time]).to_i,
      timeout: result[:timeout]
    }
  end

  def build_test_command(include_ui)
    if include_ui
      # Exclude visual test classes - they require manual inspection
      skip_visual = ' -skip-testing:SaneVideoUITests/SaneSmartFeaturesVisualTests ' \
                    '-skip-testing:SaneVideoUITests/VisualEditingTests ' \
                    '-skip-testing:SaneVideoUITests/VisualRecordingTests'
      "xcodebuild test -scheme SaneVideo -destination 'platform=macOS,arch=arm64'#{skip_visual} 2>&1"
    else
      "xcodebuild test -scheme SaneVideo -destination 'platform=macOS,arch=arm64' -only-testing:SaneVideoTests 2>&1"
    end
  end

  def execute_with_logging(cmd, timeout_seconds)
    success = false
    timed_out = false

    begin
      File.open('test_output.txt', 'w') do |log_file|
        puts '   📝 Full logs: test_output.txt'

        Timeout.timeout(timeout_seconds) do
          Open3.popen2e(cmd) do |stdin, stdout_err, wait_thr|
            stdin.close

            stdout_err.each_line do |line|
              line = line.chomp
              log_file.puts(line)
              yield(line) if block_given?
            end

            success = wait_thr.value.success?
          end
        end
      end
    rescue Timeout::Error
      timed_out = true
      handle_timeout(timeout_seconds)
    end

    { success: success && !timed_out, timeout: timed_out }
  end

  def handle_progress_update(line, state)
    # Parse test progress
    case line
    when /Test Case.*'(.+)'/
      state[:current_test] = ::Regexp.last_match(1)
      state[:tests_run] += 1
      elapsed = (Time.now - state[:start_time]).to_i
      spinner = state[:spinner_chars][state[:spinner_idx] % state[:spinner_chars].length]
      print "\r#{spinner} Running: #{state[:current_test]} (#{state[:tests_run]} tests, #{elapsed}s)    "
      state[:spinner_idx] += 1
      state[:last_update] = Time.now
    when /Test Suite.*passed|Test Suite.*failed/, /BUILD (SUCCEEDED|FAILED)/, /error:|warning:|❌|✅/
      print "\r"
      puts "   #{line}"
    when /Testing|Building/
      if Time.now - state[:last_update] > 2
        spinner = state[:spinner_chars][state[:spinner_idx] % state[:spinner_chars].length]
        print "\r#{spinner} #{line}    "
        state[:spinner_idx] += 1
        state[:last_update] = Time.now
      end
    end
  end

  def handle_timeout(timeout_seconds)
    puts "\n\n⏱️  TIMEOUT: Test run exceeded #{timeout_seconds}s"
    puts '   This usually means a test is stuck or waiting for user input'
    puts '   Check for permission dialogs or infinite loops'
    puts "   Tip: Use './Scripts/monitor_tests.sh' for more detailed monitoring"

    # Force kill on timeout - be very aggressive
    puts '🔪 Force killing all test processes...'

    # Kill in multiple waves to ensure cleanup
    3.times do |attempt|
      system("pkill -9 -f 'xcodebuild test' 2>/dev/null")
      system('killall -9 xcodebuild 2>/dev/null')
      system('killall -9 SaneVideo 2>/dev/null')
      system("pkill -9 -f 'SaneVideo' 2>/dev/null")
      system("pkill -9 -f 'xctest' 2>/dev/null")
      system("pkill -9 -f 'testmanagerd' 2>/dev/null")
      system("pkill -9 -f 'grant_permissions' 2>/dev/null")
      sleep(0.5) if attempt < 2
    end

    puts '✅ Processes killed'
  end

  def clean(args)
    nuclear = args.include?('--nuclear')

    puts '🧹 --- [ SANEMASTER CLEAN ] ---'

    if nuclear
      puts '⚠️  NUCLEAR CLEAN - Removing all build artifacts...'
      system('rm -rf ~/Library/Developer/Xcode/DerivedData/SaneVideo-*')
      system('rm -rf .derivedData')
      system('rm -rf fastlane/test_output')
      system('rm -rf /tmp/SaneVideo*')
      system('rm -f test_output.txt')
      puts '✅ Nuclear clean complete.'
    else
      puts 'Standard clean...'
      system('xcodebuild clean -scheme SaneVideo 2>&1 > /dev/null')
      system('rm -f test_output.txt')
      puts '✅ Clean complete.'
    end
  end

  def reset_permissions
    puts '🔐 --- [ SANEMASTER RESET PERMISSIONS ] ---'
    puts "Resetting TCC privacy permissions for #{@bundle_id}..."

    %w[Camera Microphone ScreenRecording].each do |service|
      print "  Resetting #{service}... "
      system("tccutil reset #{service} #{@bundle_id} 2>&1 > /dev/null")
      puts '✅'
    end

    puts "\n✅ Permissions reset. App will prompt again on next launch."
  end

  def check_permission_status
    puts 'Checking TCC database...'
    # NOTE: TCC database is protected, so we can't directly read it
    # But we can check if permissions are set by trying to access
    puts '  ℹ️  Run app to see current permission status'
  end

  def audit_project
    puts '🔍 --- [ SANEMASTER ACCESSIBILITY AUDIT ] ---'

    project_path = 'SaneVideo.xcodeproj/project.pbxproj'
    unless File.exist?(project_path)
      puts "❌ Project file not found. Run 'xcodegen generate' first."
      return
    end

    require 'xcodeproj'
    project = Xcodeproj::Project.open(project_path)
    swift_files = []

    puts '📂 Scanning Swift files for missing identifiers...'
    project.files.each do |file|
      next unless file.path.end_with?('.swift')
      next if file.path.include?('Test') # Skip test files

      # Use full path if available
      swift_files << file.real_path
    end

    missing_count = 0
    ui_components = %w[Button TextField Toggle Slider Picker]

    swift_files.uniq.each do |path|
      next unless File.exist?(path)

      content = File.read(path)

      ui_components.each do |component|
        # Heuristic: Find UI components
        # We search globally but track position to avoid repeated index() calls
        last_pos = 0
        while (start_idx = content.index(/\b#{component}\s*\(/, last_pos))
          # Find the next 3000 characters for context (closures can be very large in SwiftUI)
          context = content[start_idx..(start_idx + 3000)] || ''

          # Check if accessibilityIdentifier is present in the chain
          unless context.include?('accessibilityIdentifier')
            puts "  ⚠️  Potential missing ID: #{component} in #{File.basename(path)} (near line #{content[0..start_idx].count("\n") + 1})"
            missing_count += 1
          end

          last_pos = start_idx + 1 # Move past this one
        end
      end
    end

    if missing_count.zero?
      puts '✅ Audit Passed: All detected interactive elements have identifiers.'
    else
      puts "\n❗ Audit Found #{missing_count} potential gaps in accessibility coverage."
    end
  end

  def run_lint
    puts '🎨 --- [ SANEMASTER LINT ] ---'
    if system('bundle exec fastlane lint')
      puts '✅ Linting complete.'
    else
      puts '❌ Linting failed or SwiftLint not found.'
    end
  end

  def run_quality_report
    puts '📊 --- [ SANEMASTER QUALITY ] ---'
    if system('bundle exec fastlane quality')
      puts '✅ Quality report generation complete.'
    else
      puts '❌ Quality report generation failed.'
    end
  end

  # ============================================================================
  # Test Reference Validation
  # ============================================================================
  # Validates that all accessibility identifiers referenced in UI tests
  # actually exist in the UI code. Prevents tests from referencing non-existent
  # UI elements (like the EditTabButton issue we just fixed).
  # ============================================================================

  def validate_test_references
    puts '🔍 --- [ VALIDATE TEST REFERENCES ] ---'
    puts 'Checking that all test references match UI code...'

    # Extract identifiers from UI code
    ui_identifiers = extract_ui_identifiers
    puts "  Found #{ui_identifiers.count} identifiers in UI code"

    # Extract references from test code
    test_references = extract_test_references
    puts "  Found #{test_references.count} references in test code"

    # Find mismatches
    missing_in_ui = test_references - ui_identifiers
    missing_in_tests = ui_identifiers - test_references

    # Report issues
    if missing_in_ui.any?
      puts "\n❌ CRITICAL: Tests reference non-existent identifiers:"
      missing_in_ui.sort.each do |id|
        # Find which test file references it
        files = find_references_in_files(id)
        files.each do |file|
          puts "   - '#{id}' referenced in #{file}"
        end
      end
      puts "\n💡 Fix: Remove test references or add identifier to UI code"
      puts "   Run: grep -r \"#{missing_in_ui.first}\" SaneVideoUITests/"
      exit 1
    end

    if missing_in_tests.any?
      puts "\n⚠️  WARNING: UI has identifiers not tested:"
      missing_in_tests.sort.each do |id|
        puts "   - #{id}"
      end
      puts "\n💡 Consider: Add tests for these identifiers or remove them from UI"
    end

    puts "\n✅ All test references are valid!"
    puts "   UI identifiers: #{ui_identifiers.count}"
    puts "   Test references: #{test_references.count}"
    return unless ui_identifiers.any?

    coverage = (test_references.count.to_f / ui_identifiers.count * 100).round(1)
    puts "   Coverage: #{coverage}%"
  end

  def extract_ui_identifiers
    identifiers = Set.new

    # First, extract from AccessibilityIdentifiers enum (most reliable)
    identifiers_file = 'SaneVideo/Core/Testing/AccessibilityIdentifiers.swift'
    if File.exist?(identifiers_file)
      content = File.read(identifiers_file)
      # Pattern: static let identifierName = "IdentifierValue"
      content.scan(/static let \w+ = ["']([^"']+)["']/) do |match|
        identifiers << match[0]
      end
    end

    # Also find all accessibilityIdentifier("...") in Views (fallback for legacy code)
    Dir.glob('SaneVideo/**/*.swift').each do |file|
      next if file.include?('/Tests/') || file.include?('/Mocks/')
      next if file.include?('AccessibilityIdentifiers.swift') # Skip the enum itself
      next unless File.exist?(file)

      content = File.read(file)

      # Pattern: .accessibilityIdentifier("SomeIdentifier")
      content.scan(/\.accessibilityIdentifier\(["']([^"']+)["']\)/) do |match|
        identifiers << match[0]
      end

      # Pattern: accessibilityIdentifier("SomeIdentifier")
      content.scan(/accessibilityIdentifier\(["']([^"']+)["']\)/) do |match|
        identifiers << match[0]
      end

      # Pattern: AccessibilityIdentifiers.identifierName (using the enum)
      content.scan(/AccessibilityIdentifiers\.(\w+)/) do |match|
        # Look up the value from the enum file
        enum_content = File.read(identifiers_file) if File.exist?(identifiers_file)
        enum_content&.scan(/static let #{match[0]} = ["']([^"']+)["']/) do |enum_match|
          identifiers << enum_match[0]
        end
      end
    end

    identifiers.to_a
  end

  def extract_test_references
    identifiers = Set.new

    # System button labels that are not accessibility identifiers
    system_buttons = %w[Allow OK Ignore Cancel Continue Get Started Next Previous]
    system_buttons_pattern = Regexp.new("^(#{system_buttons.join('|')})$", Regexp::IGNORECASE)

    # Load AccessibilityIdentifiers enum values for lookup
    identifiers_file = 'SaneVideo/Core/Testing/AccessibilityIdentifiers.swift'
    enum_values = {}
    if File.exist?(identifiers_file)
      enum_content = File.read(identifiers_file)
      enum_content.scan(/static let (\w+) = ["']([^"']+)["']/) do |name, value|
        enum_values[name] = value
      end
    end

    # Find all test references in UITests
    Dir.glob('SaneVideoUITests/**/*.swift').each do |file|
      next unless File.exist?(file)

      content = File.read(file)

      # Pattern 1: AccessibilityIdentifiers.identifierName (PREFERRED - type-safe)
      content.scan(/AccessibilityIdentifiers\.(\w+)/) do |match|
        enum_name = match[0]
        if enum_values[enum_name]
          identifiers << enum_values[enum_name]
        else
          puts "  ⚠️  Warning: Unknown enum value AccessibilityIdentifiers.#{enum_name} in #{File.basename(file)}"
        end
      end

      # Pattern 2: app.buttons["Identifier"], app.textFields["Identifier"], etc.
      # Matches: app.buttons["RecordButton"], app.windows["MainWindow"], etc.
      content.scan(/app\.(?:buttons|textFields|sliders|switches|segmentedControls|windows|sheets|dialogs|alerts|otherElements)\["([^"]+)"\]/) do |match|
        id = match[0]
        # Skip system buttons (these are labels, not identifiers)
        next if system_buttons_pattern.match?(id)

        identifiers << id
      end

      # Pattern 3: .matching(identifier: "Identifier")
      # Matches: app.buttons.matching(identifier: "RecordButton")
      content.scan(/\.matching\(identifier:\s*["']([^"']+)["']\)/) do |match|
        id = match[0]
        next if system_buttons_pattern.match?(id)

        identifiers << id
      end

      # Pattern 4: Descendants matching
      # Matches: app.descendants(matching: .any).matching(identifier: "TimelineClip")
      content.scan(/app\.descendants\(matching:.*?\)\.matching\(identifier:\s*["']([^"']+)["']\)/) do |match|
        id = match[0]
        next if system_buttons_pattern.match?(id)

        identifiers << id
      end

      # Pattern 5: Query chains (nested)
      # Matches: app.windows["MainWindow"].buttons["RecordButton"]
      content.scan(/\.(?:buttons|textFields|sliders|switches|segmentedControls|windows|sheets|dialogs|alerts|otherElements)\["([^"]+)"\]/) do |match|
        id = match[0]
        next if system_buttons_pattern.match?(id)

        identifiers << id
      end

      # Pattern 6: Windows matching
      # Matches: app.windows.matching(identifier: "Settings")
      content.scan(/app\.windows\.matching\(identifier:\s*["']([^"']+)["']\)/) do |match|
        id = match[0]
        next if system_buttons_pattern.match?(id)

        identifiers << id
      end
    end

    # Filter out system identifiers and common false positives
    identifiers.reject do |id|
      id.start_with?('_XCUI:', 'NS', 'com.apple') ||
        system_buttons_pattern.match?(id) ||
        id.match?(/^[A-Z][a-z]+ [A-Z][a-z]+$/) # Simple title case (likely labels)
    end.to_a
  end

  def find_references_in_files(identifier)
    files = []
    Dir.glob('SaneVideoUITests/**/*.swift').each do |file|
      next unless File.exist?(file)

      content = File.read(file)
      files << File.basename(file) if content.include?(identifier)
    end
    files.uniq
  end

  def check_binary
    puts '🛡️ --- [ SANEMASTER BINARY AUDIT ] ---'

    # 1. Find the binary path
    puts 'Searching for production binary...'
    build_settings = `xcodebuild -scheme SaneVideo -showBuildSettings 2>/dev/null`
    target_build_dir = build_settings.match(/TARGET_BUILD_DIR = (.*)/)&.[](1)
    executable_path = build_settings.match(/EXECUTABLE_PATH = (.*)/)&.[](1)

    return puts '❌ Error: Could not determine binary path. Build the app first.' unless target_build_dir && executable_path

    full_path = File.join(target_build_dir, executable_path)
    return puts "❌ Error: Binary not found at #{full_path}. Run 'SaneMaster verify' first." unless File.exist?(full_path)

    # 2. Check for debug symbols (nm)
    print '  Checking for debug symbols... '
    `nm -u "#{full_path}" 2>&1` # -u shows undefined symbols, often a sign of debug info if unstripped
    debug_indicators = `nm "#{full_path}" 2>&1`

    if debug_indicators.include?('DEBUG') || debug_indicators.include?('assertions')
      puts '⚠️  POTENTIAL UNSTRIPPED SYMBOLS FOUND'
    else
      puts '✅'
    end

    # 3. Check architecture (lipo)
    print '  Verifying architectures... '
    archs = `lipo -info "#{full_path}"`
    puts "✅ (#{archs.strip.split(': ').last})"

    puts '✅ Binary audit complete.'
  end

  # --- CORE Commands ---

  def diagnose(path, dump: false)
    puts '🔬 --- [ SANEMASTER DIAGNOSE ] ---'

    @diagnostics_dir = File.join(Dir.tmpdir, 'SaneVideo_Diagnostics')
    FileUtils.mkdir_p(@diagnostics_dir)

    # 1. Find latest .xcresult
    xcresult = path || find_latest_xcresult

    unless xcresult && File.exist?(xcresult)
      puts '❌ No .xcresult bundle found.'
      puts '   Run tests first: ./Scripts/SaneMaster.rb verify'
      return
    end

    puts "📦 Analyzing result: #{xcresult}"

    # 2. Export diagnostics (use new xcresulttool API)
    export_path = File.join(@diagnostics_dir, "diagnostics_#{Time.now.strftime('%Y%m%d_%H%M%S')}")
    FileUtils.mkdir_p(export_path)

    # Try new API first, fall back to legacy if needed
    export_cmd = "xcrun xcresulttool export diagnostics --path '#{xcresult}' --output-path '#{export_path}' 2>&1"
    export_result = `#{export_cmd}`

    # Fall back to legacy API if new one fails
    if export_result.include?('error') || export_result.include?('Error')
      export_cmd = "xcrun xcresulttool export --legacy --type directory --path '#{xcresult}' --output-path '#{export_path}' 2>&1"
      export_result = `#{export_cmd}`
    end

    if export_result.include?('error') || export_result.include?('Error')
      puts "  Cannot read xcresult: #{export_result.lines.first}"
      puts '❌ Failed to export diagnostics.'
      return
    end

    puts "  ✅ Exported to: #{export_path}"

    # 3. Analyze App Logs
    analyze_app_logs(export_path)

    # 4. Analyze Test Logs
    analyze_test_logs(export_path) if dump

    puts "\n✅ Diagnosis complete."
  end

  def analyze_app_logs(_export_path)
    app_log = find_app_log
    if app_log
      puts "\n  📱 App Log: #{app_log}"
      puts '  --- App Runtime Insights ---'

      File.foreach(app_log) do |line|
        # Filter for important events
        case line
        when /error|Error|ERROR|crash|Crash|CRASH|exception|Exception/
          puts "  ❌ #{line.strip}"
        when /warning|Warning|WARNING/
          puts "  ⚠️  #{line.strip}"
        when /✅|🎬|📊|🔍/
          puts "  ℹ️  #{line.strip}"
        end
      end
    else
      puts '  ⚠️  No App Log found.'
    end
  end

  def analyze_test_logs(_export_path)
    # 2. Analyze Test Runner Log (XCTest Output)
    test_log = find_test_log
    if test_log
      puts "\n  📄 Test Log: #{test_log}"
      puts '  --- Test Runner Insights ---'

      printing_hierarchy = false
      hierarchy_lines_count = 0

      File.foreach(test_log) do |line|
        # Hierarchy Dump Start
        # Match "Dumping Hierarchy", "Dumping Sheet Descendants", "Dumping Sheet Hierarchy", etc.
        if line.match?(/dumping.*hierarchy|dumping.*descendants|dumping.*sheet/i)
          puts "  📄 ... Hierarchy Dump Start [matches '#{line.strip}'] ..."
          printing_hierarchy = true
          hierarchy_lines_count = 0
          next
        end

        # Stop printing hierarchy only on clear delimiters or limit
        if printing_hierarchy
          if line.include?("Test Case '-[") || hierarchy_lines_count > 1000
            printing_hierarchy = false
            puts '  📄 ... Hierarchy Dump End ...'
          else
            # Indent hierarchy lines for readability
            puts "    #{line}"
            hierarchy_lines_count += 1
            next
          end
        end

        # Standard Filters
        # Print my custom debugs
        puts "  🔍 #{line.strip}" if line.match?(/debug:/i)
        # Print failure reasons
        puts "  ❌ #{line.strip}" if line.include?('failure') || line.include?('Assertion failed') || line.include?('crashed') || line.include?('segfault')
        # Print UI Test specific waits that timed out
        puts "  ⏳ #{line.strip}" if line.include?('Waiting') && line.include?('for')
      end
    else
      puts '  ⚠️  No Test Runner Log found.'
    end
  end

  def find_app_log
    # Prioritize the app binary's log over the test runner's log
    logs = Dir.glob(File.join(@diagnostics_dir, '**', 'StandardOutputAndStandardError*.txt'))
    app_log = logs.find { |f| f.include?('com.sanevideo.SaneVideo') }
    app_log || logs.first
  end

  def find_test_log
    logs = Dir.glob(File.join(@diagnostics_dir, '**', 'StandardOutputAndStandardError*.txt'))
    logs.find { |f| f.include?('xctest') || f.include?('Test') }
  end

  def find_latest_xcresult
    # Priority: 1. System DerivedData (xcodebuild default), 2. Local DerivedData, 3. Fastlane output, 4. Tmp directory
    system_dd_logs = Dir.glob(File.expand_path('~/Library/Developer/Xcode/DerivedData/SaneVideo-*/Logs/Test/*.xcresult'))
    dd_logs = Dir.glob('.derivedData/Logs/Test/*.xcresult')
    fl_logs = Dir.glob('fastlane/test_output/*.xcresult')
    tmp_logs = Dir.glob('/tmp/*.xcresult')

    (system_dd_logs + dd_logs + fl_logs + tmp_logs).max_by { |f| File.mtime(f) }
  end

  def find_dead_code
    puts '🔍 --- [ DEAD CODE DETECTION ] ---'

    unless system('which periphery > /dev/null 2>&1')
      puts '❌ Periphery not found. Install with: brew install peripheryapp/periphery/periphery'
      return
    end

    puts 'Scanning for unused code...'
    puts ''

    # Run Periphery with the project scheme
    project_path = File.join(Dir.pwd, 'SaneVideo.xcodeproj')
    unless File.exist?(project_path)
      puts "❌ Project not found at #{project_path}"
      return
    end

    # Build arguments for Periphery
    build_args = [
      '--project', project_path,
      '--schemes', 'SaneVideo',
      '--format', 'xcode'
    ]

    # Run Periphery scan
    system('periphery', 'scan', *build_args)

    exit_code = $CHILD_STATUS.exitstatus

    puts ''
    if exit_code.zero?
      puts '✅ No unused code detected!'
    else
      puts '⚠️  Unused code detected. Review the output above.'
      puts '💡 Tip: Review each item carefully before removing - some may be used via reflection or tests.'
    end
  end

  def check_deprecations
    puts '🔍 --- [ DEPRECATION WARNINGS CHECK ] ---'
    puts 'Scanning for deprecated API usage...'
    puts ''

    project_path = File.join(Dir.pwd, 'SaneVideo.xcodeproj')
    unless File.exist?(project_path)
      puts "❌ Project not found at #{project_path}"
      return
    end

    # Build and capture ALL warnings (not just errors)
    puts 'Building to capture deprecation warnings...'
    puts ''

    # Use clean build to ensure we catch all warnings
    build_output = `xcodebuild -project #{project_path} -scheme SaneVideo -destination 'platform=macOS,arch=arm64' clean build 2>&1`

    # Extract deprecation warnings (case-insensitive)
    deprecation_warnings = build_output.lines.select do |line|
      line.downcase.include?('deprecated') ||
        line.include?('was deprecated') ||
        line.include?('is deprecated')
    end.map(&:strip).reject(&:empty?).uniq

    if deprecation_warnings.empty?
      puts '✅ No deprecation warnings found!'
      return
    end

    puts "⚠️  Found #{deprecation_warnings.length} deprecation warning(s):"
    puts ''

    # Group by file
    warnings_by_file = {}
    deprecation_warnings.each do |warning|
      # Extract file path from warning (format: /path/to/file.swift:line:column: warning: ...)
      if warning =~ /^([^:]+\.swift):(\d+):(\d+):\s+warning:\s+(.+)$/
        file = File.basename(::Regexp.last_match(1))
        line = ::Regexp.last_match(2)
        message = ::Regexp.last_match(4)
        warnings_by_file[file] ||= []
        warnings_by_file[file] << { line: line, message: message }
      elsif warning.include?('warning:') && warning.include?('.swift')
        # Try alternative format
        parts = warning.split(':')
        if parts.length >= 4
          file = File.basename(parts[0])
          line = parts[1]
          message = parts[3..].join(':').strip
          warnings_by_file[file] ||= []
          warnings_by_file[file] << { line: line, message: message }
        end
      else
        # Fallback for warnings without file info
        warnings_by_file['[Other]'] ||= []
        warnings_by_file['[Other]'] << { line: nil, message: warning }
      end
    end

    # Display grouped warnings
    warnings_by_file.each do |file, warnings|
      puts "📄 #{file}"
      warnings.each do |w|
        if w[:line]
          puts "   Line #{w[:line]}: #{w[:message]}"
        else
          puts "   #{w[:message]}"
        end
      end
      puts ''
    end

    # Check for known fixable deprecations
    fixable = []
    deprecation_warnings.each do |warning|
      if warning.include?('CIColorKernel') && warning.include?('init(source:)')
        fixable << 'CIColorKernel.init(source:) - Consider using Metal-based CIKernel or suppress with CI_SILENCE_GL_DEPRECATION'
      elsif warning.include?('onChange(of:perform:)')
        fixable << 'onChange(of:perform:) - Already fixed (uses new onChange syntax)'
      elsif warning.include?('AVAssetExportSession.export()')
        fixable << 'AVAssetExportSession.export() - Documented with TODO, consider migrating to states(updateInterval:)'
      end
    end

    if fixable.any?
      puts '💡 Known deprecations:'
      fixable.uniq.each { |f| puts "   - #{f}" }
      puts ''
    end

    puts ''
    puts "⚠️  Total: #{deprecation_warnings.length} deprecation warning(s)"
    puts '💡 Tip: Review each warning and update to modern APIs when possible'
  end

  def swift6_check
    puts '🔍 --- [ SWIFT 6 CONCURRENCY COMPLIANCE ] ---'
    puts 'Scanning for concurrency patterns...'
    puts ''

    source_dir = File.join(Dir.pwd, 'SaneVideo')
    unless File.directory?(source_dir)
      puts "❌ Source directory not found: #{source_dir}"
      return
    end

    # Define patterns to check
    patterns = {
      '@MainActor' => { count: 0, files: [], description: 'Main actor isolated types/methods' },
      'actor ' => { count: 0, files: [], description: 'Custom actors' },
      'nonisolated' => { count: 0, files: [], description: 'Non-isolated members' },
      '@Sendable' => { count: 0, files: [], description: 'Sendable closures' },
      '@unchecked Sendable' => { count: 0, files: [], description: 'Unchecked Sendable conformances' },
      'nonisolated(unsafe)' => { count: 0, files: [], description: 'Unsafe nonisolated (for threading edge cases)' },
      'Task { @MainActor' => { count: 0, files: [], description: 'Tasks dispatched to MainActor' },
      'Task.detached' => { count: 0, files: [], description: 'Detached tasks' },
      ': Sendable' => { count: 0, files: [], description: 'Sendable protocol conformance' }
    }

    # Problems to flag
    problems = []

    # Scan all Swift files
    swift_files = Dir.glob("#{source_dir}/**/*.swift")
    swift_files.each do |file|
      content = File.read(file)
      rel_path = file.sub("#{Dir.pwd}/", '')

      patterns.each do |pattern, data|
        matches = content.scan(/#{Regexp.escape(pattern)}/).count
        next unless matches.positive?

        data[:count] += matches
        data[:files] << rel_path unless data[:files].include?(rel_path)
      end

      # Check for potential issues
      lines = content.lines
      lines.each_with_index do |line, idx|
        line_num = idx + 1

        # Flag DispatchQueue usage (should use async/await)
        if line.include?('DispatchQueue.main') && !line.include?('//')
          problems << { file: rel_path, line: line_num, issue: 'DispatchQueue.main - consider Task { @MainActor }' }
        end

        # Flag completion handlers without @Sendable
        if line =~ /completion:\s*@escaping\s+\(/ && !line.include?('@Sendable')
          problems << { file: rel_path, line: line_num, issue: 'Completion handler may need @Sendable' }
        end

        # Flag assumeIsolated in deinit (common crash pattern)
        if line.include?('assumeIsolated') && content.include?('deinit')
          problems << { file: rel_path, line: line_num, issue: 'assumeIsolated near deinit - potential crash' }
        end
      end
    end

    # Report findings
    puts '📊 Concurrency Pattern Usage:'
    puts ''

    patterns.each_value do |data|
      emoji = data[:count].positive? ? '✅' : '⚪'
      puts "  #{emoji} #{data[:description]}: #{data[:count]} usages in #{data[:files].length} files"
    end

    total_usages = patterns.values.map { |d| d[:count] }.sum
    puts ''
    puts "  📈 Total concurrency annotations: #{total_usages}"

    # Grade the codebase
    grade = if total_usages > 400 && patterns['actor '][:count] > 10
              'A'
            elsif total_usages > 200 && patterns['@MainActor'][:count] > 20
              'B'
            elsif total_usages > 50
              'C'
            else
              'D'
            end

    puts ''
    puts "  🎯 Swift 6 Readiness Grade: #{grade}"
    puts ''

    # Report problems
    if problems.any?
      puts '⚠️  Potential Issues Found:'
      problems.group_by { |p| p[:file] }.each do |file, issues|
        puts "  📄 #{file}"
        issues.each do |issue|
          puts "     Line #{issue[:line]}: #{issue[:issue]}"
        end
      end
    else
      puts '✅ No potential concurrency issues detected!'
    end
    puts ''

    # Recommendations
    puts '💡 Swift 6 Recommendations:'
    puts '   - All public types with mutable state should be actors or @MainActor'
    puts '   - Use Task { @MainActor in } instead of DispatchQueue.main.async'
    puts '   - Mark completion handlers as @Sendable for cross-actor safety'
    puts '   - Use nonisolated for computed properties that access immutable data'
    puts ''

    # Check for strict concurrency build setting
    project_file = File.join(Dir.pwd, 'project.yml')
    return unless File.exist?(project_file)

    yml_content = File.read(project_file)
    if yml_content.include?('SWIFT_STRICT_CONCURRENCY') && yml_content.include?('complete')
      puts '✅ Strict concurrency checking enabled (complete mode)'
    elsif yml_content.include?('SWIFT_STRICT_CONCURRENCY')
      puts '⚠️  Strict concurrency checking enabled (consider upgrading to complete)'
    else
      puts '⚠️  Consider adding SWIFT_STRICT_CONCURRENCY: complete to project.yml'
    end
  end

  def run_test_suite(args)
    quick_mode = args.include?('--quick')
    full_mode = args.include?('--full')
    ci_mode = args.include?('--ci')

    puts '🧪 --- [ COMPREHENSIVE TEST SUITE ] ---'
    puts 'Running all available validation tools...'
    puts ''

    results = {
      passed: [],
      failed: [],
      warnings: [],
      skipped: []
    }

    # Always run fast checks
    puts '📋 Phase 1: Fast Validation Checks'
    puts '─' * 50

    # 1. Build verification
    puts "\n1️⃣  Build Verification..."
    build_output = `xcodebuild -project SaneVideo.xcodeproj -scheme SaneVideo -destination "platform=macOS,arch=arm64" build 2>&1`
    if build_output.include?('BUILD SUCCEEDED')
      puts '   ✅ Build successful'
      results[:passed] << 'Build'
    else
      puts '   ❌ Build failed'
      # Show last few lines of build output for context
      error_lines = build_output.lines.select { |l| l.include?('error:') || l.include?('BUILD FAILED') }.last(3)
      error_lines.each { |line| puts "      #{line.strip}" } if error_lines.any?
      results[:failed] << 'Build'
      puts '   ⚠️  Skipping remaining checks due to build failure'
      print_summary(results)
      exit 1
    end

    # 2. XcodeGen sync check
    puts "\n2️⃣  XcodeGen Project Sync..."
    # Check if project.yml exists and is newer than project.pbxproj
    project_yml = 'project.yml'
    project_pbx = 'SaneVideo.xcodeproj/project.pbxproj'
    if File.exist?(project_yml) && File.exist?(project_pbx)
      yml_mtime = File.mtime(project_yml)
      pbx_mtime = File.mtime(project_pbx)
      if yml_mtime <= pbx_mtime
        puts '   ✅ Project in sync'
        results[:passed] << 'XcodeGen'
      else
        puts '   ⚠️  Project out of sync (run: xcodegen generate)'
        results[:warnings] << 'XcodeGen'
      end
    else
      puts '   ⚠️  Cannot verify sync (missing files)'
      results[:warnings] << 'XcodeGen'
    end

    # 3. Linting
    puts "\n3️⃣  Code Linting..."
    lint_output = `./Scripts/SaneMaster.rb lint 2>&1`
    if lint_output.include?('✅') || $CHILD_STATUS.success?
      puts '   ✅ Linting passed'
      results[:passed] << 'Lint'
    else
      puts '   ⚠️  Linting issues found (non-blocking)'
      results[:warnings] << 'Lint'
    end

    # 4. Test reference validation
    puts "\n4️⃣  Test Reference Validation..."
    test_ref_output = `./Scripts/SaneMaster.rb validate_test_references 2>&1`
    if test_ref_output.include?('✅') && $CHILD_STATUS.success?
      puts '   ✅ All test references valid'
      results[:passed] << 'Test References'
    else
      puts '   ❌ Test reference validation failed'
      results[:failed] << 'Test References'
    end

    # 5. Documentation sync
    puts "\n5️⃣  Documentation Sync..."
    docs_output = `./Scripts/SaneMaster.rb check_docs 2>&1`
    if docs_output.include?('✅') || !docs_output.include?('drift')
      puts '   ✅ Documentation in sync'
      results[:passed] << 'Documentation'
    else
      puts '   ⚠️  Documentation drift detected (non-blocking)'
      results[:warnings] << 'Documentation'
    end

    # Phase 2: Medium checks (unless quick mode)
    if quick_mode
      results[:skipped] << 'Mocks'
      results[:skipped] << 'Deprecations'
    else
      puts "\n📋 Phase 2: Medium Validation Checks"
      puts '─' * 50

      # 6. Mock verification
      puts "\n6️⃣  Mock Synchronization..."
      mock_output = `./Scripts/SaneMaster.rb verify_mocks 2>&1`
      if mock_output.include?('✅') || $CHILD_STATUS.success?
        puts '   ✅ Mocks in sync'
        results[:passed] << 'Mocks'
      else
        puts '   ⚠️  Mock sync issues (non-blocking)'
        results[:warnings] << 'Mocks'
      end

      # 7. Deprecation checking (can be slow)
      if full_mode || ci_mode
        puts "\n7️⃣  Deprecation Check..."
        deprec_output = `./Scripts/SaneMaster.rb check_deprecations 2>&1`
        if deprec_output.include?('✅') || !deprec_output.include?('Found')
          puts '   ✅ No deprecations found'
          results[:passed] << 'Deprecations'
        else
          puts '   ⚠️  Deprecations found (non-blocking)'
          results[:warnings] << 'Deprecations'
        end
      else
        puts "\n7️⃣  Deprecation Check... (skipped, use --full to include)"
        results[:skipped] << 'Deprecations'
      end
    end

    # Phase 3: Slow checks (only in full mode)
    if full_mode && !ci_mode
      puts "\n📋 Phase 3: Deep Analysis Checks"
      puts '─' * 50

      # 8. Dead code detection
      puts "\n8️⃣  Dead Code Detection..."
      dead_code_output = `./Scripts/SaneMaster.rb dead_code 2>&1`
      if dead_code_output.include?('✅') || $CHILD_STATUS.success?
        puts '   ✅ No dead code detected'
        results[:passed] << 'Dead Code'
      else
        puts '   ⚠️  Dead code detected (review output)'
        results[:warnings] << 'Dead Code'
      end
    else
      results[:skipped] << 'Dead Code'
    end

    # Print summary
    print_summary(results)

    # Exit with appropriate code (warnings don't fail CI)
    exit(results[:failed].any? ? 1 : 0)
  end

  def print_summary(results)
    puts "\n#{'=' * 50}"
    puts '📊 TEST SUITE SUMMARY'
    puts '=' * 50

    if results[:passed].any?
      puts "\n✅ PASSED (#{results[:passed].count}):"
      results[:passed].each { |item| puts "   • #{item}" }
    end

    if results[:failed].any?
      puts "\n❌ FAILED (#{results[:failed].count}):"
      results[:failed].each { |item| puts "   • #{item}" }
    end

    if results[:warnings].any?
      puts "\n⚠️  WARNINGS (#{results[:warnings].count}):"
      results[:warnings].each { |item| puts "   • #{item}" }
    end

    if results[:skipped].any?
      puts "\n⏭️  SKIPPED (#{results[:skipped].count}):"
      results[:skipped].each { |item| puts "   • #{item}" }
    end

    total = results[:passed].count + results[:failed].count + results[:warnings].count
    puts "\n📈 Total Checks: #{total}"
    puts "   ✅ Passed: #{results[:passed].count}"
    puts "   ❌ Failed: #{results[:failed].count}"
    puts "   ⚠️  Warnings: #{results[:warnings].count}"

    if results[:failed].any?
      puts "\n❌ Test suite failed. Fix issues above before proceeding."
    elsif results[:warnings].any?
      puts "\n⚠️  Test suite passed with warnings. Review warnings above."
    else
      puts "\n✅ All checks passed!"
    end
  end

  def analyze_crashes(args)
    puts '💥 --- [ CRASH REPORT ANALYSIS ] ---'
    puts 'Analyzing SaneVideo crash reports for patterns...'
    puts ''

    crash_dir = File.expand_path('~/Library/Logs/DiagnosticReports')
    crash_files = Dir.glob(File.join(crash_dir, 'SaneVideo-*.ips')).sort_by { |f| File.mtime(f) }.reverse

    if crash_files.empty?
      puts '✅ No crash reports found. The app appears stable!'
      return
    end

    # Parse options
    limit = 10
    show_details = args.include?('--details') || args.include?('-d')
    recent_only = args.include?('--recent') || args.include?('-r')

    if recent_only
      # Only last 24 hours
      cutoff = Time.now - (24 * 60 * 60)
      crash_files = crash_files.select { |f| File.mtime(f) > cutoff }
      puts '📅 Showing crashes from last 24 hours only'
    end

    puts "📊 Found #{crash_files.count} crash report(s)"
    puts ''

    # Collect crash data
    crash_data = []
    crash_files.first(50).each do |file|
      content = File.read(file)
      # Find JSON start
      json_start = content.index("\n{")
      next unless json_start

      json_data = JSON.parse(content[json_start..])
      exception = json_data['exception'] || {}

      # Find faulting thread
      threads = json_data['threads'] || []
      faulting_thread = threads.find { |t| t['triggered'] }

      if faulting_thread
        frames = faulting_thread['frames'] || []
        signature = frames.first(4).map { |f| (f['symbol'] || '?')[0..35] }.join(' -> ')
        queue = faulting_thread['queue'] || 'unknown'

        # Get SaneVideo-specific frame
        app_frame = frames.first(15).find do |f|
          src = f['sourceFile'] || ''
          sym = f['symbol'] || ''
          src.include?('SaneVideo') || sym.include?('SaneVideo')
        end

        crash_data << {
          file: File.basename(file),
          time: File.mtime(file),
          type: exception['type'] || 'Unknown',
          signal: exception['signal'] || 'Unknown',
          subtype: exception['subtype'],
          signature: signature,
          queue: queue,
          app_frame: app_frame ? "#{app_frame['symbol']} (#{File.basename(app_frame['sourceFile'] || 'unknown')}:#{app_frame['sourceLine']})" : nil,
          thread_index: json_data['faultingThread'] || 0
        }
      end
    rescue StandardError => _e
      # Skip unparseable files
    end

    # Analyze patterns
    puts '📈 CRASH TYPE DISTRIBUTION'
    puts '─' * 50
    type_counts = crash_data.group_by { |c| c[:type] }.transform_values(&:count)
    type_counts.sort_by { |_, count| -count }.each do |type, count|
      pct = (count.to_f / crash_data.count * 100).round(1)
      puts "  #{type}: #{count} (#{pct}%)"
    end
    puts ''

    puts '🧵 FAULTING THREAD DISTRIBUTION'
    puts '─' * 50
    thread_counts = crash_data.group_by { |c| c[:thread_index] }.transform_values(&:count)
    thread_counts.sort_by { |_, count| -count }.each do |thread, count|
      pct = (count.to_f / crash_data.count * 100).round(1)
      label = thread.zero? ? 'Main Thread' : "Thread #{thread}"
      puts "  #{label}: #{count} (#{pct}%)"
    end
    puts ''

    puts '🔍 TOP CRASH SIGNATURES (Pattern Detection)'
    puts '─' * 50
    sig_counts = crash_data.group_by { |c| c[:signature] }.transform_values(&:count)
    sig_counts.sort_by { |_, count| -count }.first(8).each do |sig, count|
      puts "  [#{count}x] #{sig}"
    end
    puts ''

    # App-specific frames
    app_frames = crash_data.map { |c| c[:app_frame] }.compact
    if app_frames.any?
      puts '📱 SANEVIDEO CODE FRAMES'
      puts '─' * 50
      frame_counts = app_frames.group_by(&:itself).transform_values(&:count)
      frame_counts.sort_by { |_, count| -count }.first(10).each do |frame, count|
        puts "  [#{count}x] #{frame}"
      end
      puts ''
    end

    # Known patterns analysis
    puts '⚠️  KNOWN ISSUE PATTERNS'
    puts '─' * 50

    known_patterns = {
      'Actor Isolation (MainActor.assumeIsolated)' => crash_data.count { |c| c[:signature].include?('dispatch_assert_queue') },
      'Object Deallocated (Timer/Publisher)' => crash_data.count { |c| c[:signature].include?('isMainExecutor') && c[:subtype]&.include?('0x000000000000001') },
      'Test Cleanup (XCTMemoryChecker)' => crash_data.count { |c| c[:signature].include?('XCTMemoryChecker') },
      'Memory Corruption (objc_release)' => crash_data.count { |c| c[:signature].start_with?('objc_release') && !c[:signature].include?('XCTMemoryChecker') }
    }

    known_patterns.each do |pattern, count|
      next if count.zero?

      pct = (count.to_f / crash_data.count * 100).round(1)
      puts "  #{pattern}: #{count} (#{pct}%)"
    end
    puts ''

    # Recent crashes
    if show_details
      puts '📋 RECENT CRASHES (Details)'
      puts '─' * 50
      crash_data.first(limit).each do |crash|
        puts "  📄 #{crash[:file]}"
        puts "     Time: #{crash[:time].strftime('%Y-%m-%d %H:%M:%S')}"
        puts "     Type: #{crash[:type]} (#{crash[:signal]})"
        puts "     Queue: #{crash[:queue]}"
        puts "     Signature: #{crash[:signature]}"
        puts "     App Frame: #{crash[:app_frame]}" if crash[:app_frame]
        puts ''
      end
    else
      puts '💡 Tip: Use --details (-d) for individual crash details'
      puts '💡 Tip: Use --recent (-r) for last 24 hours only'
    end

    # Summary
    puts '📊 SUMMARY'
    puts '─' * 50
    puts "  Total crashes analyzed: #{crash_data.count}"
    puts "  Oldest: #{crash_data.last[:time].strftime('%Y-%m-%d %H:%M')}" if crash_data.any?
    puts "  Newest: #{crash_data.first[:time].strftime('%Y-%m-%d %H:%M')}" if crash_data.any?

    main_thread_crashes = crash_data.count { |c| c[:thread_index].zero? }
    puts "  ⚠️  #{main_thread_crashes}/#{crash_data.count} crashes on Main Thread - check UI/state code" if main_thread_crashes > crash_data.count * 0.5

    test_crashes = crash_data.count { |c| c[:signature].include?('XCT') }
    return unless test_crashes.positive?

    puts "  ℹ️  #{test_crashes} crash(es) in test cleanup - review async test handling"
  end

  def enter_test_mode(_args)
    puts '🧪 --- [ TEST MODE ] ---'
    puts 'Preparing clean testing environment...'
    puts ''

    screenshots_dir = File.join(Dir.pwd, 'Screenshots')
    log_file = File.expand_path('~/Movies/SaneVideo/SaneVideo_Debug.log')
    crash_dir = File.expand_path('~/Library/Logs/DiagnosticReports')

    # Step 1: Kill any running instances
    puts '1️⃣  Killing existing SaneVideo processes...'
    system('killall -9 SaneVideo 2>/dev/null')
    puts '   ✅ Done'
    puts ''

    # Step 2: Show recent screenshots
    puts '2️⃣  Screenshots in project:'
    if Dir.exist?(screenshots_dir)
      screenshots = Dir.glob(File.join(screenshots_dir, '*.png')).sort_by { |f| File.mtime(f) }.reverse
      if screenshots.any?
        puts "   📁 #{screenshots_dir}"
        screenshots.first(5).each do |f|
          mtime = File.mtime(f).strftime('%Y-%m-%d %H:%M:%S')
          puts "   📸 #{File.basename(f)} (#{mtime})"
        end
        puts "   ... and #{screenshots.count - 5} more" if screenshots.count > 5
        puts ''
        puts '   💡 To clear old screenshots: rm Screenshots/*.png'
      else
        puts '   (no screenshots found)'
      end
    else
      puts "   (screenshots directory doesn't exist)"
    end
    puts ''

    # Step 3: Show recent crash/hang reports
    puts '3️⃣  Recent diagnostic reports:'
    crash_files = Dir.glob(File.join(crash_dir, 'SaneVideo-*.ips')).sort_by { |f| File.mtime(f) }.reverse
    hang_files = Dir.glob(File.join(crash_dir, 'SaneVideo-*.{spin,hang}')).sort_by { |f| File.mtime(f) }.reverse

    if crash_files.any?
      puts '   Crashes:'
      crash_files.first(3).each do |f|
        mtime = File.mtime(f).strftime('%Y-%m-%d %H:%M:%S')
        puts "   💥 #{File.basename(f)} (#{mtime})"
      end
      puts "   ... and #{crash_files.count - 3} more crashes" if crash_files.count > 3
    else
      puts '   💥 No crash reports'
    end

    if hang_files.any?
      puts '   Hangs/Spins:'
      hang_files.first(2).each do |f|
        mtime = File.mtime(f).strftime('%Y-%m-%d %H:%M:%S')
        puts "   🔄 #{File.basename(f)} (#{mtime})"
      end
    end

    # Check for recent xcresult bundles
    xcresult_dir = File.expand_path('~/Library/Developer/Xcode/DerivedData')
    xcresults = Dir.glob(File.join(xcresult_dir, 'SaneVideo-*/Logs/Test/*.xcresult')).sort_by { |f| File.mtime(f) }.reverse
    if xcresults.any?
      latest = xcresults.first
      mtime = File.mtime(latest).strftime('%Y-%m-%d %H:%M:%S')
      puts "   📊 Latest test result: #{File.basename(latest)} (#{mtime})"
    end
    puts ''

    # Step 4: Build the app
    puts '4️⃣  Building app...'
    build_success = system('xcodebuild -scheme SaneVideo -destination "platform=macOS" build 2>&1 | grep -E "(BUILD|error:)" | tail -5')
    unless build_success
      puts '   ❌ Build failed! Fix errors before continuing.'
      return
    end
    puts '   ✅ Build succeeded'
    puts ''

    # Step 5: Launch the app
    puts '5️⃣  Launching app...'
    launch_app([])
    sleep 2
    puts ''

    # Step 6: Show log file status
    puts '6️⃣  Debug log status:'
    if File.exist?(log_file)
      mtime = File.mtime(log_file).strftime('%Y-%m-%d %H:%M:%S')
      size = (File.size(log_file) / 1024.0).round(1)
      puts "   📋 #{log_file}"
      puts "   📅 Last updated: #{mtime} (#{size}KB)"
    else
      puts '   (log file not created yet - will appear after app runs)'
    end
    puts ''

    puts '═' * 60
    puts '🧪 TEST MODE READY'
    puts '═' * 60
    puts ''
    puts 'Diagnostic commands:'
    puts '  ./Scripts/SaneMaster.rb logs --follow    # Watch debug log live'
    puts '  ./Scripts/SaneMaster.rb logs             # Show recent debug log'
    puts '  ./Scripts/SaneMaster.rb crashes          # Analyze crash reports'
    puts '  ./Scripts/SaneMaster.rb diagnose         # Analyze latest xcresult'
    puts '  open Screenshots/                        # View screenshots'
    puts ''
    puts 'All diagnostic locations:'
    puts '  📋 Debug log:    ~/Movies/SaneVideo/SaneVideo_Debug.log'
    puts '  📸 Screenshots:  Screenshots/'
    puts '  💥 Crashes:      ~/Library/Logs/DiagnosticReports/SaneVideo-*.ips'
    puts '  📊 Test results: ~/Library/Developer/Xcode/DerivedData/SaneVideo-*/Logs/Test/'
    puts ''
    puts 'Session timestamps to cross-reference:'
    puts "  🕐 Session started: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    puts ''

    # Post-fix checklist reminder
    puts '⚠️  POST-FIX CHECKLIST (after each bug fix):'
    puts '  [ ] Regression test added?'
    puts '  [ ] Similar bugs checked elsewhere?'
    puts '  [ ] Changes committed to git?'
    puts '  [ ] Can explain fix in plain English?'
    puts ''
  end

  def show_app_logs(args)
    puts '📋 --- [ APPLICATION LOGS ] ---'

    # Primary log location: ~/Movies/SaneVideo/SaneVideo_Debug.log
    # This file is overwritten on each app launch for easy debugging
    log_file = File.expand_path('~/Movies/SaneVideo/SaneVideo_Debug.log')

    # Parse options
    tail_count = 50
    follow_mode = args.include?('--follow') || args.include?('-f')

    args.each_with_index do |arg, i|
      tail_count = args[i + 1].to_i if arg == '--tail' && args[i + 1]
    end

    unless File.exist?(log_file)
      puts '❌ No log file found at: ~/Movies/SaneVideo/SaneVideo_Debug.log'
      puts ''
      puts 'To generate logs:'
      puts '  1. Rebuild the app: ./Scripts/SaneMaster.rb verify'
      puts '  2. Launch the app: ./Scripts/SaneMaster.rb launch'
      puts '  3. Run this command again'
      return
    end

    mtime = File.mtime(log_file)
    size = File.size(log_file) / 1024.0
    puts '📁 Log file: ~/Movies/SaneVideo/SaneVideo_Debug.log'
    puts "   Last updated: #{mtime.strftime('%Y-%m-%d %H:%M:%S')} (#{size.round(1)}KB)"
    puts '─' * 60

    if follow_mode
      puts 'Following log file (Ctrl+C to stop)...'
      puts ''
      exec("tail -f '#{log_file}'")
    else
      lines = File.readlines(log_file)
      if lines.length > tail_count
        puts "(showing last #{tail_count} of #{lines.length} lines)"
        puts ''
        puts lines.last(tail_count).join
      else
        puts lines.join
      end
    end
  end

  # --- Verify MCP Configuration (Rule #10: MISSING TOOL = UPGRADE SANEMASTER) ---
  def verify_mcps
    puts '🔍 --- [ MCP VERIFICATION ] ---'
    puts ''

    # SOP-required MCPs from DEVELOPMENT.md
    sop_mcps = {
      'apple-docs' => { package: '@mweinbach/apple-docs-mcp@latest', required: true },
      'github' => { package: '@modelcontextprotocol/server-github', required: true },
      'memory' => { package: '@modelcontextprotocol/server-memory', required: true },
      'context7' => { package: '@upstash/context7-mcp@latest', required: true },
      'XcodeBuildMCP' => { package: 'xcodebuildmcp@latest', required: true }
    }

    config_paths = ['.mcp.json', '.cursor/mcp.json']
    all_valid = true

    config_paths.each do |config_path|
      next unless File.exist?(config_path)

      puts "📄 Checking: #{config_path}"
      begin
        config = JSON.parse(File.read(config_path))
        servers = config['mcpServers'] || {}

        sop_mcps.each do |name, info|
          if servers.key?(name)
            package = servers[name]['args']&.last || 'unknown'
            puts "   ✅ #{name}: Configured (#{package})"
          else
            puts "   ❌ #{name}: MISSING"
            all_valid = false if info[:required]
            puts "      ⚠️  #{info[:note]}" if info[:note]
          end
        end

        # Check for extra servers
        extra = servers.keys - sop_mcps.keys
        puts "   📦 Extra servers: #{extra.join(', ')}" if extra.any?

        puts "   📊 Total: #{servers.length} servers"
        puts ''
      rescue JSON::ParserError => e
        puts "   ❌ Invalid JSON: #{e.message}"
        all_valid = false
        puts ''
      end
    end

    # Check if .cursor/mcp.json exists (Cursor-specific)
    unless File.exist?('.cursor/mcp.json')
      puts '⚠️  .cursor/mcp.json not found (Cursor may use this location)'
      puts '   Run: cp .mcp.json .cursor/mcp.json'
      all_valid = false
    end

    puts ''
    if all_valid
      puts '✅ All required MCPs are configured'
      puts ''
      puts '💡 To verify MCPs are working in Cursor:'
      puts '   1. Restart Cursor'
      puts '   2. Check Settings > MCP Tools'
      puts '   3. Or run: cursor-agent mcp list'
    else
      puts '❌ Some required MCPs are missing or misconfigured'
      puts ''
      puts '💡 Fix by:'
      puts '   1. Add missing MCPs to .mcp.json'
      puts '   2. Copy to .cursor/mcp.json: cp .mcp.json .cursor/mcp.json'
      puts '   3. Restart Cursor'
    end
  end
end

# Execute
SaneMaster.new.run(ARGV)
