#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'tmpdir'
require 'optparse'

# ==============================================================================
# SaneMaster: Professional Automation Suite for SaneVideo
# ==============================================================================
# Commands:
#   diagnose [path] - Run intelligent heuristics on a .xcresult bundle.
#   doctor          - Check environment, mock assets, and permissions.
#   verify          - Build and run tests with auto-diagnostics.
#   clean           - Safely wipe build cache and test states.
#   reset           - Wipe TCC privacy permissions (Camera, Mic, Screen).
#   audit           - Scan project for missing accessibility identifiers.
#   setup           - Install missing gems and system dependencies.
#   lint            - Run SwiftLint and auto-fix common issues.
#   quality         - Generate Ruby quality reports (HTML).
# ==============================================================================

class SaneMaster
  def initialize
    @bundle_id = "com.sanevideo.SaneVideo" # Centralized for tccutil
  end

  def run(args)
    if args.empty?
      print_help
      return
    end

    command = args.shift
    case command
    when "diagnose" 
      path = nil
      dump = false
      
      # Simple arg parsing
      args.each_with_index do |arg, i|
        if arg == "--path"
          path = args[i+1]
        elsif arg == "--dump"
          dump = true
        elsif !arg.start_with?("-") && path.nil?
          path = arg
        end
      end
      
      diagnose(path, dump: dump)
    when "doctor"   then doctor
    when "verify"   then verify(args)
    when "clean"    then clean(args)
    when "reset"    then reset_permissions
    when "audit"    then audit_project
    when "setup"    then setup_environment
    when "lint"     then run_lint
    when "quality"  then run_quality_report
    when "check_binary" then check_binary
    when "restore"  then restore_xcode
    when "gen_assets" then generate_test_assets
    else
      puts "❌ Unknown command: #{command}"
      print_help
    end
  end

  # --- PRO Commands ---

  def restore_xcode
    puts "🛠️ --- [ SANEMASTER RESTORE ] ---"
    puts "Fixing common Xcode/Launch Services issues..."
    
    # 1. Reset Launch Services
    lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if File.exist?(lsregister)
      print "  Resetting Launch Services database... "
      system("#{lsregister} -kill -r -domain local -domain system -domain user")
      puts "✅"
    end

    # 2. Restart Dock (often helps with icon/launch issues)
    print "  Restarting Dock... "
    system("killall Dock")
    puts "✅"

    # 3. Nuclear Clean
    clean(["--nuclear"])
    
    puts "\n✅ System restored. Try opening the project in Xcode again."
  end

  def setup_environment
    puts "🛠️ --- [ SANEMASTER SETUP ] ---"
    
    print "📦 Running bundle install... "
    if system("bundle install --path vendor/bundle > /dev/null 2>&1")
      puts "✅"
    else
      puts "❌ FAILED"
      puts "   💡 Suggestion: Run 'gem install bundler' first."
    end

    # 2. Check System Tools
    %w[ffmpeg swiftlint].each do |tool|
      print "🔧 Checking for '#{tool}'... "
      if system("which #{tool} > /dev/null 2>&1")
        puts "✅"
      else
        puts "❌ MISSING"
        puts "   💡 Suggestion: brew install #{tool}"
      end
    end
    
    puts "✅ Setup check complete."
  end

  def generate_test_assets
    puts "🎥 --- [ SANEMASTER ASSETS ] ---"
    
    unless system("which ffmpeg > /dev/null 2>&1")
      puts "❌ Error: ffmpeg is required to generate assets."
      puts "   👉 Run 'brew install ffmpeg'"
      return
    end

    assets_dir = File.join(Dir.pwd, "Tests/Assets")
    FileUtils.mkdir_p(assets_dir)
    
    target = File.join(assets_dir, "test_silence.mp4")
    
    print "   Generating 12s test video (Audio -> Silence -> Audio)... "
    
    cmd = [
      "ffmpeg -y -v error",
      "-f lavfi -i \"sine=frequency=440:duration=5\"",
      "-f lavfi -i \"anullsrc=channel_layout=stereo:sample_rate=44100:duration=2\"",
      "-f lavfi -i \"sine=frequency=880:duration=5\"",
      "-f lavfi -i \"color=c=blue:s=1280x720:d=12\"",
      "-filter_complex \"[0:a][1:a][2:a]concat=n=3:v=0:a=1[aout]\"",
      "-map 3:v -map \"[aout]\"",
      "-c:v libx264 -pix_fmt yuv420p",
      "-c:a aac -b:a 128k",
      "\"#{target}\""
    ].join(" ")
    
    if system(cmd)
      puts "✅ Created: #{target}"
    else
      puts "❌ FAILED"
    end
  end

  def reset_permissions
    puts "🔐 --- [ SANEMASTER RESET ] ---"
    puts "Resetting TCC privacy permissions for #{@bundle_id}..."
    
    services = %w[Camera Microphone ScreenCapture All]
    services.each do |service|
      print "  Wiping #{service}... "
      # tccutil reset [Service] [BundleID]
      if system("tccutil reset #{service} #{@bundle_id} > /dev/null 2>&1")
        puts "✅"
      else
        puts "⚠️"
      end
    end
    puts "✅ Privacy permissions cleared. The app will prompt for access on next launch."
  end

  def audit_project
    puts "🔍 --- [ SANEMASTER AUDIT ] ---"
    begin
      require 'xcodeproj'
    rescue LoadError
      return puts "❌ Error: 'xcodeproj' gem not found. Run 'SaneMaster setup' first."
    end
    
    project_path = "SaneVideo.xcodeproj"
    unless File.exist?(project_path)
      return puts "❌ Error: Project not found at #{project_path}"
    end

    project = Xcodeproj::Project.open(project_path)
    swift_files = []
    
    puts "📂 Scanning Swift files for missing identifiers..."
    project.files.each do |file|
      next unless file.path.end_with?(".swift")
      next if file.path.include?("Test") # Skip test files
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
          context = content[start_idx..start_idx+3000] || ""
          
          # Check if accessibilityIdentifier is present in the chain
          unless context.include?("accessibilityIdentifier")
            puts "  ⚠️  Potential missing ID: #{component} in #{File.basename(path)} (near line #{content[0..start_idx].count("\n") + 1})"
            missing_count += 1
          end
          
          last_pos = start_idx + 1 # Move past this one
        end
      end
    end

    if missing_count == 0
      puts "✅ Audit Passed: All detected interactive elements have identifiers."
    else
      puts "\n❗ Audit Found #{missing_count} potential gaps in accessibility coverage."
    end
  end

  def run_lint
    puts "🎨 --- [ SANEMASTER LINT ] ---"
    if system("bundle exec fastlane lint")
      puts "✅ Linting complete."
    else
      puts "❌ Linting failed or SwiftLint not found."
    end
  end

  def run_quality_report
    puts "📊 --- [ SANEMASTER QUALITY ] ---"
    if system("bundle exec fastlane quality")
      puts "✅ Quality report generation complete."
    else
      puts "❌ Quality report generation failed."
    end
  end

  def check_binary
    puts "🛡️ --- [ SANEMASTER BINARY AUDIT ] ---"
    
    # 1. Find the binary path
    puts "Searching for production binary..."
    build_settings = `xcodebuild -scheme SaneVideo -showBuildSettings 2>/dev/null`
    target_build_dir = build_settings.match(/TARGET_BUILD_DIR = (.*)/)&.[](1)
    executable_path = build_settings.match(/EXECUTABLE_PATH = (.*)/)&.[](1)
    
    unless target_build_dir && executable_path
      return puts "❌ Error: Could not determine binary path. Build the app first."
    end
    
    full_path = File.join(target_build_dir, executable_path)
    unless File.exist?(full_path)
      return puts "❌ Error: Binary not found at #{full_path}. Run 'SaneMaster verify' first."
    end
    
    # 2. Check for debug symbols (nm)
    print "  Checking for debug symbols... "
    symbols = `nm -u "#{full_path}" 2>&1` # -u shows undefined symbols, often a sign of debug info if unstripped
    debug_indicators = content = `nm "#{full_path}" 2>&1`
    
    if debug_indicators.include?("DEBUG") || debug_indicators.include?("assertions")
      puts "⚠️  POTENTIAL UNSTRIPPED SYMBOLS FOUND"
    else
      puts "✅"
    end
    
    # 3. Check architecture (lipo)
    print "  Verifying architectures... "
    archs = `lipo -info "#{full_path}"`
    puts "✅ (#{archs.strip.split(": ").last})"
    
    puts "✅ Binary audit complete."
  end

  # --- CORE Commands ---

  def diagnose(xcresult_path = nil, dump: false)
    master = UITestMaster.new(xcresult_path, dump: dump)
    if master.export_diagnostics
      master.run_heuristics
    else
      puts "❌ Failed to export diagnostics."
    end
  end

  def doctor
    puts "🩺 --- [ SANEMASTER DOCTOR ] ---"
    # Basic Checks
    puts "📂 Project: #{File.directory?("SaneVideo.xcodeproj") ? "✅ Found" : "❌ Missing"}"
    test_video = "Tests/Assets/test_silence.mp4"
    puts "📁 Mock Video: #{File.exist?(test_video) ? "✅ Found" : "⚠️  Missing"}"
    
    # Tool Checks
    %w[ffmpeg swiftlint fastlane xcodeproj].each do |tool|
      status = system("which #{tool} > /dev/null 2>&1") || is_gem_installed?(tool)
      puts "🔧 #{tool}: #{status ? "✅" : "❌"}"
    end

    # File Line Count Audit (<500 lines)
    puts "\n📏 Auditing file sizes (Standard: <500 lines)..."
    over_limit = []
    Dir.glob("**/*.swift").each do |path|
      next if path.include?("Test") || path.include?("Packages/") || path.include?(".derivedData/") || path.include?("vendor/")
      line_count = File.foreach(path).inject(0) { |c, _| c + 1 }
      over_limit << { path: path, count: line_count } if line_count > 500
    end

    if over_limit.empty?
      puts "✅ All Swift files are within the 500-line modularity limit."
    else
      puts "⚠️  Modularity Violations:"
      over_limit.each do |f|
        puts "  🔴 #{f[:path]}: #{f[:count]} lines"
      end
    end
  end

  def verify(args = [])
    puts "🚀 --- [ SANEMASTER VERIFY ] ---"
    
    # Start the Permission Monitor in the background
    puts "🛡️  Launching Permission Monitor (God Mode)..."
    monitor_pid = spawn("/usr/bin/osascript Scripts/grant_permissions.applescript SaneVideo", [:out, :err] => "/dev/null")
    Process.detach(monitor_pid)

    success = system("bundle exec fastlane verify")
    
    # Cleanup monitor (though it self-terminates after 60s)
    begin
        Process.kill("TERM", monitor_pid)
    rescue
        # Ignore if already dead
    end
    
    if success
      puts "\n✅ VERIFICATION PASSED."
    else
      bundle_path = "fastlane/test_output/SaneVideo.xcresult"
      puts "\n❌ VERIFICATION FAILED. Triggering intelligent diagnostics..."
      diagnose(bundle_path)
    end
  end

  def clean(args = [])
    puts "🧹 --- [ SANEMASTER CLEAN ] ---"
    nuclear = args.include?("--nuclear")
    
    puts "Cleaning build artifacts..."
    system("xcodebuild clean -scheme SaneVideo -quiet")
    
    if nuclear
      puts "☢️  PERFORMING NUCLEAR CLEAN..."
      [
        "~/Library/Developer/Xcode/DerivedData",
        "./.derivedData",
        "./.swiftpm",
        "./build"
      ].each do |path|
        expanded_path = File.expand_path(path)
        if File.exist?(expanded_path)
          print "  Removing #{path}... "
          FileUtils.rm_rf(expanded_path)
          puts "✅"
        end
      end
    end

    FileUtils.rm_rf(Dir.glob("/tmp/*.xcresult"))
    FileUtils.rm_rf("/tmp/SaneVideo")
    # Clean root logs
    Dir.glob("*.log").each { |f| FileUtils.rm_f(f) }
    Dir.glob("build_log.txt").each { |f| FileUtils.rm_f(f) }

    puts "✅ Clean complete."
  end

  private

  def is_gem_installed?(name)
    `gem list #{name} -i`.strip == "true"
  end

  def print_help
    puts "SaneMaster: Professional High-Level Power Tools for SaneVideo"
    puts "Note: Use XcodeBuildMCP for primitive build/test/UI operations."
    puts "\nUsage: ./Scripts/SaneMaster.rb <command> [options]"
    puts "\nSaneVideo Power Commands:"
    puts "  verify [--launch]  Build, test, and run intelligent diagnostics on failure."
    puts "  diagnose [path]    Deep analysis of SwiftUI traps in an .xcresult bundle."
    puts "  doctor             Check environment health and enforce 500-line modularity."
    puts "  clean [--nuclear]  Wipe all caches, derived data, and temporary artifacts."
    puts "  audit              Scan project for missing accessibility identifiers."
    puts "  restore            Restore Launch Services and fix broken Xcode icons."
    puts "  reset              Wipe all TCC privacy permissions (Camera, Mic, Screen)."
    puts "  setup              Provision environment (gems, system dependencies)."
    puts "  lint               Run SwiftLint with auto-fix and full audit."
    puts "  quality            Generate Ruby quality reports (HTML)."
  end
end

# --- Diagnostic Engine ---

class UITestMaster
  def initialize(xcresult_path = nil, dump: false)
    @xcresult_path = xcresult_path || find_latest_xcresult
    @diagnostics_dir = nil
    @dump_logs = dump
  end

  def export_diagnostics
    return false unless @xcresult_path
    puts "📦 Analyzing result: #{@xcresult_path}"

    output = `xcrun xcresulttool get --path "#{@xcresult_path}" --format json --legacy 2>&1`
    if $?.exitstatus != 0
      puts "  Cannot read xcresult: #{output}"
      return false 
    end
    
    begin
      data = JSON.parse(output)
    rescue JSON::ParserError => e
      puts "  JSON Parse Error: #{e.message}"
      return false
    end
    
    # Deep search for diagnosticsRef
    def find_diag_id(obj)
      return obj["diagnosticsRef"]["id"]["_value"] if obj.is_a?(Hash) && obj.key?("diagnosticsRef")
      
      if obj.is_a?(Hash)
        obj.each_value do |v|
          found = find_diag_id(v)
          return found if found
        end
      elsif obj.is_a?(Array)
        obj.each do |v|
          found = find_diag_id(v)
          return found if found
        end
      end
      nil
    end

    diag_id = find_diag_id(data)

    if diag_id.nil?
      puts "  ⚠️  Could not find diagnosticsRef ID in xcresult tree." 
      return false 
    end

    @diagnostics_dir = Dir.mktmpdir("sanemaster_")
    # Use --legacy flag for reliability with older xcresulttool versions or specific environments
    `xcrun xcresulttool export --legacy --path "#{@xcresult_path}" --id "#{diag_id}" --type directory --output-path "#{@diagnostics_dir}"`
    true
  end

  def run_heuristics
    # 1. Analyze App Log (Standard Output)
    app_log = find_app_log
    if app_log
      puts "  📄 App Log: #{File.basename(app_log)}"
      content = File.read(app_log)

      if @dump_logs
        puts "\n  📜 --- FULL APP LOG START ---"
        puts content
        puts "  📜 --- FULL APP LOG END ---\n"
      end
      
      puts "  --- App Log Heuristics ---"
      # Error Detection
      puts "  🔴 CMIO CONNECTION INVALID (Tahoe Race)" if content.include?("CMIOExtensionProviderHostContext.m") && content.include?("Connection invalid")
      puts "  🔴 CMIO IDENTITY ERROR (Code -7)" if content.include?("kCSIdentityInvalidPosixNameErr") && content.include?("Code -7")
      
      # Noise Detection
      hydration_calls = content.scan(/hydrateProject called!/).size
      if hydration_calls > 5
        puts "  🔴 EXCESSIVE HYDRATION: #{hydration_calls} calls detected! (Expected < 5 at boot)"
      elsif hydration_calls > 0
        puts "  🟡 Project hydration occurred (#{hydration_calls} calls)."
      end

      # Security & Performance
      puts "  🔴 SECURITY SCOPE LEAK: Uneven lock/unlock count" if content.scan(/🔐 Started security scope/).size != content.scan(/🔓 Stopped security scope/).size
      
      # 🎨 VFX & Metal Graphics Errors
      vfx_errors = content.scan(/patching invalid duplicated core entity handle|couldn't remap entity|script wasn't bound to runtime|Render pass format not ready/).size
      puts "  🔴 VFX/GRAPHICS ENGINE FAILURE: #{vfx_errors} errors detected (Metal/VFXNode mismatch)." if vfx_errors > 0

      # 🖼️ Asset & Symbol Errors
      missing_symbols = content.scan(/No symbol named '(.*)' found in system symbol set/).flatten
      missing_symbols.uniq.each do |sym|
        puts "  🔴 MISSING SYSTEM SYMBOL: '#{sym}' (Check target OS version / bundle ID)."
      end

      # 🏗️ Layout & UI Recursion
      if content.include?("_NSDetectedLayoutRecursion") || content.include?("layoutSubtreeIfNeeded")
        puts "  🔴 LAYOUT RECURSION DETECTED: UI is fighting itself (Infinite layout loop)."
      end

      # General Catch-all for Proactive Debugging
      content.each_line do |line|
        if line.match?(/error:|fault:|panic:|fatal/i) && !line.include?("MLE5Engine") # MLE5 is often just info
          puts "  ❌ CRITICAL LOG: #{line.strip}"
        elsif line.match?(/warning:|⚠️/i) && !line.include?("com.apple") # Filter system noise
          puts "  🟡 LOG WARNING: #{line.strip}"
        end
      end

      # General Verification
      puts "  🔴 WINDOW FOCUS BLOCKED" if content.include?("makeKeyWindow] called on") && content.include?("returned NO")
      puts "  🟡 DOUBLE BOOTSTRAP DETECTED" if content.scan(/Calling bootstrapEditorForTesting/).size > 1
      puts "  🔴 MASKING DETECTED: SwiftUI tree is 'Disabled'." if content.include?("SaneVideo, {{Disabled}}")
      puts "  ✅ Window restoration logic verified." if content.include?("Restoring main window")
      puts "  ✅ Export sheet presentation detected." if content.include?("🎨 ExportView: appeared")
    else
      puts "  ⚠️  No App Log found."
    end

    # 2. Analyze Test Runner Log (XCTest Output)
    test_log = find_test_log
    if test_log
      puts "\n  📄 Test Log: #{test_log}"
      puts "  --- Test Runner Insights ---"
      
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
             puts "  📄 ... Hierarchy Dump End ..."
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
        if line.include?("failure") || line.include?("Assertion failed") || line.include?("crashed") || line.include?("segfault")
             puts "  ❌ #{line.strip}" 
        end
        # Print UI Test specific waits that timed out
        puts "  ⏳ #{line.strip}" if line.include?("Waiting") && line.include?("for")
      end
    else
      puts "  ⚠️  No Test Runner Log found."
    end
  end

  def find_app_log
    # Prioritize the app binary's log over the test runner's log
    logs = Dir.glob(File.join(@diagnostics_dir, "**", "StandardOutputAndStandardError*.txt"))
    app_log = logs.find { |f| f.include?("com.sanevideo.SaneVideo") }
    app_log || logs.first
  end

  def find_test_log
    Dir.glob(File.join(@diagnostics_dir, "**", "Session-*.log")).first
  end

  def find_latest_xcresult
    # Priority: 1. DerivedData logs (most recent test), 2. Tmp directory
    dd_logs = Dir.glob(".derivedData/Logs/Test/*.xcresult")
    tmp_logs = Dir.glob("/tmp/*.xcresult")
    
    (dd_logs + tmp_logs).max_by { |f| File.mtime(f) }
  end
end

# Execute
SaneMaster.new.run(ARGV)
