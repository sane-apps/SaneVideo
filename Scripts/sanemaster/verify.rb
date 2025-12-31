# frozen_string_literal: true

module SaneMasterModules
  # Build, test execution, permissions, test validation
  module Verify
    def doctor
      puts '🏥 --- [ SANEMASTER DOCTOR ] ---'

      check_disk_space
      check_test_assets
      check_xcodegen_sync
      check_permissions
      check_mockolo
      check_xcode
      check_code_quality_tools
      check_stuck_processes
      check_derived_data

      puts "\n✅ Doctor check complete."
    end

    def verify(args)
      if test_targets_disabled?
        handle_disabled_tests(args)
        return
      end

      clean_first = args.include?('--clean')
      include_ui = args.include?('--ui')
      timeout = args.include?('--timeout') ? args[args.index('--timeout') + 1].to_i : 180

      clean([]) if clean_first

      puts '🔨 --- [ SANEMASTER VERIFY ] ---'
      puts 'Building and running tests with progress monitoring...'
      puts "⏱️  Timeout: #{timeout}s | Auto-handling permissions: ✅"
      puts include_ui ? '📱 Including UI tests (use --ui flag)' : '⚡ Unit tests only (use --ui to include UI tests)'
      puts ''

      permission_monitor_pid = grant_test_permissions
      validate_test_references unless args.include?('--skip-test-validation')

      begin
        result = run_tests_with_progress(timeout_seconds: timeout, include_ui: include_ui)

        if result[:success]
          puts "\n✅ Tests passed! (#{result[:tests_run]} tests, #{result[:duration]}s)"
        else
          puts "\n❌ Tests failed. Running diagnostics..."
          puts "⚠️  Test run timed out after #{timeout}s" if result[:timeout]
          diagnose(nil, dump: true)
        end
      ensure
        cleanup_test_processes(permission_monitor_pid)
      end
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
      swift_files = project.files.select { |f| f.path.end_with?('.swift') && !f.path.include?('Test') }.map(&:real_path)

      puts '📂 Scanning Swift files for missing identifiers...'
      missing_count = scan_for_missing_identifiers(swift_files)

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

    def validate_test_references
      puts '🔍 --- [ VALIDATE TEST REFERENCES ] ---'
      puts 'Checking that all test references match UI code...'

      ui_identifiers = extract_ui_identifiers
      puts "  Found #{ui_identifiers.count} identifiers in UI code"

      test_references = extract_test_references
      puts "  Found #{test_references.count} references in test code"

      missing_in_ui = test_references - ui_identifiers

      if missing_in_ui.any?
        puts "\n❌ CRITICAL: Tests reference non-existent identifiers:"
        missing_in_ui.sort.each do |id|
          files = find_references_in_files(id)
          files.each { |file| puts "   - '#{id}' referenced in #{file}" }
        end
        puts "\n💡 Fix: Remove test references or add identifier to UI code"
        exit 1
      end

      puts "\n✅ All test references are valid!"
      puts "   UI identifiers: #{ui_identifiers.count}"
      puts "   Test references: #{test_references.count}"
    end

    private

    def test_targets_disabled?
      project_yml = File.join(Dir.pwd, 'project.yml')
      return false unless File.exist?(project_yml)

      content = File.read(project_yml)
      content.include?('# Temporarily disabled test targets') ||
        (content.include?('# targets:') && content.include?('#   - SaneVideoTests'))
    end

    def handle_disabled_tests(args)
      puts '⚠️  Test targets are temporarily disabled due to SwiftUICore linker error (Xcode 16/macOS 26.2 bug)'
      puts '📝 Test files are preserved - they will be re-enabled when Xcode is updated'
      puts ''
      puts 'Building main app only (tests skipped)...'
      puts ''

      clean([]) if args.include?('--clean')

      puts '🔨 Building SaneVideo app...'
      result = system("xcodebuild -project SaneVideo.xcodeproj -scheme SaneVideo -destination 'platform=macOS,arch=arm64' build")
      puts ''
      if result
        puts '✅ Build succeeded (tests disabled)'
      else
        puts '❌ Build failed'
        exit 1
      end
    end

    def grant_test_permissions
      print '🔐 Granting test permissions... '
      system('tccutil reset Camera com.sanevideo.SaneVideo 2>/dev/null')
      system('tccutil reset Microphone com.sanevideo.SaneVideo 2>/dev/null')
      system('tccutil reset ScreenRecording com.sanevideo.SaneVideo 2>/dev/null')

      permission_pid = nil
      script_path = File.join(__dir__, '..', 'grant_permissions.applescript')
      if File.exist?(script_path)
        permission_pid = Process.spawn("osascript '#{script_path}' SaneVideo > /dev/null 2>&1")
        Process.detach(permission_pid)
      end

      puts '✅'
      permission_pid
    end

    def cleanup_test_processes(permission_monitor_pid = nil)
      print '🧹 Cleaning up test processes... '

      if permission_monitor_pid
        begin
          Process.kill('TERM', permission_monitor_pid) if permission_monitor_pid.positive?
        rescue Errno::ESRCH, Errno::EPERM
          # Process already dead or we don't have permission
        end
      end

      system("pkill -f 'grant_permissions.applescript' 2>/dev/null")
      system("pkill -f 'xcodebuild test' 2>/dev/null")
      system("pkill -f 'SaneVideo.*test' 2>/dev/null")
      system('pkill -9 xcodebuild 2>/dev/null')
      sleep(0.5)
      system('killall -9 xcodebuild 2>/dev/null')
      system('killall -9 SaneVideo 2>/dev/null')

      puts '✅'
    end

    def run_tests_with_progress(timeout_seconds:, include_ui: false)
      require 'timeout'
      require 'open3'

      cmd = build_test_command(include_ui)
      state = { start_time: Time.now, tests_run: 0, current_test: nil, last_update: Time.now,
                spinner_chars: ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'], spinner_idx: 0 }

      result = execute_with_logging(cmd, timeout_seconds) { |line| handle_progress_update(line, state) }

      print "\r"
      cleanup_test_processes

      { success: result[:success], tests_run: state[:tests_run], duration: (Time.now - state[:start_time]).to_i, timeout: result[:timeout] }
    end

    def build_test_command(include_ui)
      if include_ui
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
      puts '🔪 Force killing all test processes...'

      3.times do |attempt|
        system("pkill -9 -f 'xcodebuild test' 2>/dev/null")
        system('killall -9 xcodebuild 2>/dev/null')
        system('killall -9 SaneVideo 2>/dev/null')
        system("pkill -9 -f 'xctest' 2>/dev/null")
        sleep(0.5) if attempt < 2
      end

      puts '✅ Processes killed'
    end

    def check_disk_space
      puts "\n💾 Disk Space:"
      disk_info = `df -h . 2>/dev/null`.lines.last&.split || []
      return unless disk_info.length >= 4

      available = disk_info[3]
      puts "  ✅ Available: #{available}"
      puts '  ⚠️  Low disk space! Export/build may fail' if available.include?('G') && available.to_f < 10
    end

    def check_test_assets
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
        puts '     Run: ./Scripts/SaneMaster.rb gen_assets'
      end
    end

    def check_xcodegen_sync
      puts "\n📁 XcodeGen Sync:"
      project_path = 'SaneVideo.xcodeproj/project.pbxproj'
      unless File.exist?(project_path)
        puts '  ❌ Project file missing. Run: xcodegen generate'
        return
      end

      puts '  ✅ Project file exists'
      begin
        require 'xcodeproj'
        project = Xcodeproj::Project.open('SaneVideo.xcodeproj')
        project_swift_count = project.files.count { |f| f.path&.end_with?('.swift') }
        disk_swift_count = `find . -name "*.swift" -not -path "*/.*" -not -path "*/build/*" -not -path "*/vendor/*" | wc -l`.strip.to_i
        if (project_swift_count - disk_swift_count).abs > 15
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
    end

    def check_permissions
      puts "\n🔐 Permissions:"
      check_permission_status
    end

    def check_mockolo
      puts "\n🎭 Mock Generation:"
      if system('which mockolo > /dev/null 2>&1')
        version = `mockolo --version 2>&1`.strip
        puts "  ✅ Mockolo installed (#{version})"
      else
        puts '  ⚠️  Mockolo not found. Install: brew install mockolo'
      end
    end

    def check_xcode
      puts "\n🛠️  Xcode:"
      xcode_version = `xcodebuild -version 2>&1`.strip
      if xcode_version.include?('Xcode')
        puts "  ✅ #{xcode_version}"
      else
        puts '  ❌ Xcode not found'
      end
    end

    def check_code_quality_tools
      puts "\n🎨 Code Quality Tools:"
      if system('which swiftlint > /dev/null 2>&1')
        version = `swiftlint version 2>&1`.strip
        puts "  ✅ SwiftLint #{version}"
      else
        puts '  ⚠️  SwiftLint not found. Install: brew install swiftlint'
      end
    end

    def check_stuck_processes
      puts "\n🔄 Stuck Processes:"
      stuck = `pgrep -f 'xcodebuild|xctest' 2>/dev/null`.strip
      stuck_pids = stuck.split.reject do |pid|
        cmd = `ps -p #{pid} -o comm= 2>/dev/null`.strip
        cmd.include?('testmanagerd') || cmd.include?('/usr/libexec/')
      end
      if stuck_pids.empty?
        puts '  ✅ No stuck test processes'
      else
        puts "  ⚠️  Found stuck processes: #{stuck_pids.join(', ')}"
        puts '     Run: killall -9 xcodebuild xctest'
      end
    end

    def check_derived_data
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
    end

    def scan_for_missing_identifiers(swift_files)
      missing_count = 0
      ui_components = %w[Button TextField Toggle Slider Picker]

      swift_files.uniq.each do |path|
        next unless File.exist?(path)

        content = File.read(path)
        ui_components.each do |component|
          last_pos = 0
          while (start_idx = content.index(/\b#{component}\s*\(/, last_pos))
            context = content[start_idx..(start_idx + 3000)] || ''
            unless context.include?('accessibilityIdentifier')
              puts "  ⚠️  Potential missing ID: #{component} in #{File.basename(path)} (near line #{content[0..start_idx].count("\n") + 1})"
              missing_count += 1
            end
            last_pos = start_idx + 1
          end
        end
      end

      missing_count
    end

    def extract_ui_identifiers
      identifiers = Set.new

      identifiers_file = 'SaneVideo/Core/Testing/AccessibilityIdentifiers.swift'
      if File.exist?(identifiers_file)
        content = File.read(identifiers_file)
        content.scan(/static let \w+ = ["']([^"']+)["']/) { |match| identifiers << match[0] }
      end

      Dir.glob('SaneVideo/**/*.swift').each do |file|
        next if file.include?('/Tests/') || file.include?('/Mocks/') || file.include?('AccessibilityIdentifiers.swift')
        next unless File.exist?(file)

        content = File.read(file)
        content.scan(/\.accessibilityIdentifier\(["']([^"']+)["']\)/) { |match| identifiers << match[0] }
        content.scan(/accessibilityIdentifier\(["']([^"']+)["']\)/) { |match| identifiers << match[0] }
      end

      identifiers.to_a
    end

    def extract_test_references
      identifiers = Set.new
      system_buttons = %w[Allow OK Ignore Cancel Continue]

      Dir.glob('SaneVideoUITests/**/*.swift').each do |file|
        next unless File.exist?(file)

        content = File.read(file)
        content.scan(/\[["']([^"']+)["']\]/) do |match|
          id = match[0]
          identifiers << id unless system_buttons.include?(id) || id.match?(/^\d+$/)
        end
      end

      identifiers.to_a
    end

    def find_references_in_files(identifier)
      files = []
      Dir.glob('SaneVideoUITests/**/*.swift').each do |file|
        content = File.read(file)
        files << File.basename(file) if content.include?(identifier)
      end
      files
    end
  end
end
