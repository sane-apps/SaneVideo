#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SaneMaster: Professional Automation Suite for SaneVideo
# ==============================================================================
# Modular architecture - see Scripts/sanemaster/ for implementations:
#   base.rb        - Shared constants and utilities
#   memory.rb      - Memory MCP integration
#   dependencies.rb - Version checking, dependency graphs
#   generation.rb   - Test/mock generation, templates
#   diagnostics.rb  - Crash analysis, xcresult diagnosis
#   bootstrap.rb    - Environment setup, auto-update
#   test_mode.rb    - Interactive debugging workflow
#   verify.rb       - Build, test execution, permissions
#   quality.rb      - Dead code, deprecations, Swift 6 compliance
# ==============================================================================

# Load all modules
require_relative 'sanemaster/base'
require_relative 'sanemaster/memory'
require_relative 'sanemaster/dependencies'
require_relative 'sanemaster/generation'
require_relative 'sanemaster/diagnostics'
require_relative 'sanemaster/bootstrap'
require_relative 'sanemaster/test_mode'
require_relative 'sanemaster/verify'
require_relative 'sanemaster/quality'

class SaneMaster
  include SaneMasterModules::Base
  include SaneMasterModules::Memory
  include SaneMasterModules::Dependencies
  include SaneMasterModules::Generation
  include SaneMasterModules::Diagnostics
  include SaneMasterModules::Bootstrap
  include SaneMasterModules::TestMode
  include SaneMasterModules::Verify
  include SaneMasterModules::Quality

  def initialize
    @bundle_id = 'com.sanevideo.SaneVideo'
  end

  def run(args)
    if args.empty?
      print_help
      return
    end

    command = args.shift
    dispatch_command(command, args)
  end

  private

  def dispatch_command(command, args)
    case command
    # Diagnostics
    when 'diagnose'
      diagnose_args = parse_diagnose_args(args)
      diagnose(diagnose_args[:path], dump: diagnose_args[:dump])
    when 'crash_report', 'crashes'
      analyze_crashes(args)

    # Environment & Health
    when 'doctor'
      doctor
    when 'bootstrap', 'preflight', 'env'
      run_bootstrap(args)
    when 'setup'
      setup_environment
    when 'restore'
      restore_xcode

    # Build & Test
    when 'verify'
      verify(args)
    when 'clean'
      clean(args)
    when 'lint'
      run_lint
    when 'quality'
      run_quality_report
    when 'audit'
      audit_project
    when 'validate_test_references', 'validate-tests'
      validate_test_references

    # Permissions
    when 'reset'
      reset_permissions
    when 'check_permissions'
      check_permission_status

    # Generation & Verification
    when 'gen_assets'
      generate_test_assets
    when 'gen_test'
      generate_test_file(args)
    when 'gen_mock'
      generate_mocks(args)
    when 'check_xcodegen'
      check_xcodegen(args)
    when 'verify_api'
      verify_api(args)
    when 'verify_mocks'
      verify_mocks
    when 'check_protocol_changes'
      check_protocol_changes(args)
    when 'check_docs'
      verify_documentation_sync
    when 'template'
      manage_templates(args)

    # Quality Analysis
    when 'dead_code', 'find_dead_code'
      find_dead_code
    when 'check_deprecations', 'deprecations'
      check_deprecations
    when 'swift6_check', 'swift6', 'concurrency_check'
      swift6_check
    when 'test_suite', 'suite'
      run_test_suite(args)
    when 'check_binary'
      check_binary

    # Dependencies & Versions
    when 'version_check', 'versions'
      check_latest_versions(args)
    when 'ci_parity', 'ci_check'
      check_ci_parity
    when 'deps', 'dependencies'
      show_dependency_graph(args)
    when 'verify_mcps'
      verify_mcps

    # Interactive Debugging
    when 'launch', 'run'
      launch_app(args)
    when 'logs'
      show_app_logs(args)
    when 'test_mode', 'tm'
      enter_test_mode(args)

    # Memory MCP
    when 'memory_context', 'mc'
      show_memory_context(args)
    when 'memory_record', 'mr'
      record_memory_entity(args)
    when 'memory_prune', 'mp'
      prune_memory_entities(args)

    # Debug Console
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

  def parse_diagnose_args(args)
    path = nil
    dump = false

    args.each_with_index do |arg, i|
      if arg == '--path'
        path = args[i + 1]
      elsif arg == '--dump'
        dump = true
      elsif !arg.start_with?('-') && path.nil?
        path = arg
      end
    end

    { path: path, dump: dump }
  end

  def check_binary
    puts '🛡️ --- [ SANEMASTER BINARY AUDIT ] ---'

    puts 'Searching for production binary...'
    build_settings = `xcodebuild -scheme SaneVideo -showBuildSettings 2>/dev/null`
    target_build_dir = build_settings.match(/TARGET_BUILD_DIR = (.*)/)&.[](1)
    executable_path = build_settings.match(/EXECUTABLE_PATH = (.*)/)&.[](1)

    unless target_build_dir && executable_path
      puts '❌ Error: Could not determine binary path. Build the app first.'
      return
    end

    full_path = File.join(target_build_dir, executable_path)
    unless File.exist?(full_path)
      puts "❌ Error: Binary not found at #{full_path}. Run 'SaneMaster verify' first."
      return
    end

    audit_binary_symbols(full_path)
    audit_binary_architectures(full_path)

    puts '✅ Binary audit complete.'
  end

  def audit_binary_symbols(full_path)
    print '  Checking for debug symbols... '
    `nm -u "#{full_path}" 2>&1`
    debug_indicators = `nm "#{full_path}" 2>&1`

    if debug_indicators.include?('DEBUG') || debug_indicators.include?('assertions')
      puts '⚠️  POTENTIAL UNSTRIPPED SYMBOLS FOUND'
    else
      puts '✅'
    end
  end

  def audit_binary_architectures(full_path)
    print '  Verifying architectures... '
    archs = `lipo -info "#{full_path}"`
    puts "✅ (#{archs.strip.split(': ').last})"
  end

  def print_help
    puts <<~HELP
      SaneMaster - Professional Automation Suite for SaneVideo

      Commands:
        verify [--ui] [--clean] [--skip-test-validation]
          Build and run tests (unit tests by default, --ui for UI tests)

        validate_test_references (or validate-tests)
          Validate that all UI test references match actual UI code

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

        test_suite (or suite) [--quick] [--full] [--ci]
          Run comprehensive validation suite
          --quick: Fast checks only
          --full: All checks including slow ones
          --ci: CI-optimized

        crash_report (or crashes) [--details] [--recent]
          Analyze crash reports for patterns

        logs [--tail N] [--follow]
          Show SaneVideo application logs

        test_mode (or tm)
          Enter interactive debugging workflow

        bootstrap (or preflight, env)
          Full environment bootstrap
          --check-only: Report status without changes
          --rollback: Restore previous snapshot
          --no-fix: Skip auto-fixing

        versions (or version_check)
          Check installed tool versions
          --refresh (-f): Force refresh cache

        ci_parity (or ci_check)
          Compare local environment with CI

        deps (or dependencies)
          Show project dependency graph
          --dot: Output GraphViz DOT format

        template [save|apply|list|delete] [name]
          Manage project configuration templates

        memory_context (or mc)
          Show cross-session knowledge from Memory MCP

        memory_record (or mr) <type> <name>
          Record new entity to Memory MCP

        memory_prune (or mp) [--dry-run]
          Remove stale memory entities

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
end

# --- Main Entry Point ---
SaneMaster.new.run(ARGV) if __FILE__ == $PROGRAM_NAME
