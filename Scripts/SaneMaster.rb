#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'tmpdir'
require 'optparse'
require 'set'

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
    when 'audit'    then audit_project
    when 'validate_test_references', 'validate-tests' then validate_test_references
    when 'setup'    then setup_environment
    when 'lint'     then run_lint
    when 'quality'  then run_quality_report
    when 'check_binary' then check_binary
    when 'restore' then restore_xcode
    when 'gen_assets' then generate_test_assets
    when 'gen_test' then generate_test_file(args)
    when 'gen_mock' then generate_mocks(args)
    when 'check_xcodegen' then check_xcodegen(args)
    when 'verify_api' then verify_api(args)
    when 'verify_mocks' then verify_mocks
    when 'check_protocol_changes' then check_protocol_changes(args)
    when 'check_docs' then check_documentation_sync
    when 'dead_code', 'find_dead_code' then find_dead_code
    when 'check_deprecations', 'deprecations' then check_deprecations
    when 'test_suite', 'suite' then run_test_suite(args)
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
      #{options[:type] == 'ui' ? 'import XCUITest' : ''}
      #{options[:async] ? 'import AVFoundation' : ''}
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
      #{options[:type] == 'ui' ? 'import XCUITest' : ''}
      #{options[:async] ? 'import AVFoundation' : ''}
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
          # rubocop:disable Metrics/BlockNesting, Layout/LineLength
          # Add @testable import after Foundation if not present
          content.gsub!(/(import Foundation\n)/, "\\1@testable import SaneVideo\n") unless content.include?('@testable import SaneVideo')
          # Fix nonisolated sampleBufferSubject for CameraServiceProtocol
          # Replace stored property with computed property that uses MainActor.assumeIsolated
          content.gsub!(/private var _sampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never>!/,
                        'private var _sampleBufferSubjectStorage: PassthroughSubject<CMSampleBuffer, Never>!')
          content.gsub!(/(var sampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> \{)/, 'nonisolated \\1')
          content.gsub!(/(get \{ return _sampleBufferSubject \})/,
                        "get { \n            return MainActor.assumeIsolated {\n                if _sampleBufferSubjectStorage == nil {\n                    _sampleBufferSubjectStorage = PassthroughSubject<CMSampleBuffer, Never>()\n                }\n                return _sampleBufferSubjectStorage \n            }\n        }")
          content.gsub!(/(set \{ _sampleBufferSubject = newValue \})/,
                        "set { \n            MainActor.assumeIsolated {\n                _sampleBufferSubjectStorage = newValue\n            }\n        }")
          # rubocop:enable Metrics/BlockNesting, Layout/LineLength
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

    require 'xcodeproj'
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

  def check_documentation_sync
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
        
        test_suite (or suite) [--quick] [--full] [--ci]
          Run comprehensive validation suite (all static analysis tools)
          --quick: Fast checks only (lint, test references, xcodegen)
          --full: All checks including slow ones (dead code, deprecations)
          --ci: CI-optimized (excludes slow checks, includes build)
        
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
        disk_swift_count = `find SaneVideo -name "*.swift" -not -path "*/Tests/*" | wc -l`.strip.to_i
        if (project_swift_count - disk_swift_count).abs > 5 # Allow some variance
          puts "  ⚠️  File count mismatch (project: #{project_swift_count}, disk: ~#{disk_swift_count})"
          puts '     Run: xcodegen generate'
        else
          puts "  ✅ Project appears in sync (#{project_swift_count} Swift files)"
        end
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

    puts "\n✅ Doctor check complete."
  end

  def test_targets_disabled?
    # Check if test targets are commented out in project.yml
    project_yml = File.join(Dir.pwd, 'project.yml')
    return false unless File.exist?(project_yml)
    
    content = File.read(project_yml)
    # Check if test targets are commented out
    content.include?('# Temporarily disabled test targets') || 
    content.include?('# targets:') && content.include?('#   - SaneVideoTests')
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
      if result
        puts ''
        puts '✅ Build succeeded (tests disabled)'
      else
        puts ''
        puts '❌ Build failed'
        exit 1
      end
      return
    end
    
    clean_first = args.include?('--clean')
    include_ui = args.include?('--ui')
    timeout = args.include?('--timeout') ? args[args.index('--timeout') + 1].to_i : 480 # 8 min default (balanced safety)

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

    start_time = Time.now
    tests_run = 0
    current_test = nil
    last_update = Time.now
    spinner_chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
    spinner_idx = 0

    # Build command (skip UI tests unless --ui flag)
    skip_ui = include_ui ? '' : ' -only-testing:SaneVideoTests'
    cmd = "xcodebuild test -scheme SaneVideo -destination 'platform=macOS,arch=arm64'#{skip_ui} 2>&1"

    success = false
    timed_out = false

    begin
      Timeout.timeout(timeout_seconds) do
        Open3.popen2e(cmd) do |stdin, stdout_err, wait_thr|
          stdin.close

          stdout_err.each_line do |line|
            line = line.chomp

            # Parse test progress
            case line
            when /Test Case.*'(.+)'/
              current_test = ::Regexp.last_match(1)
              tests_run += 1
              elapsed = (Time.now - start_time).to_i
              print "\r#{spinner_chars[spinner_idx % spinner_chars.length]} Running: #{current_test} (#{tests_run} tests, #{elapsed}s)    "
              spinner_idx += 1
              last_update = Time.now
            when /Test Suite.*passed|Test Suite.*failed/, /BUILD (SUCCEEDED|FAILED)/, /error:|warning:|❌|✅/
              # Important messages that deserve a new line
              print "\r"
              puts "   #{line}"
            when /Testing|Building/
              # Status updates
              if Time.now - last_update > 2 # Update every 2 seconds
                print "\r#{spinner_chars[spinner_idx % spinner_chars.length]} #{line}    "
                spinner_idx += 1
                last_update = Time.now
              end
            end

            # NOTE: Permission dialogs are handled by grant_permissions.applescript running in background
          end

          success = wait_thr.value.success?
        end
      end
    rescue Timeout::Error
      timed_out = true
      puts "\n\n⏱️  TIMEOUT: Test run exceeded #{timeout_seconds}s"
      puts '   This usually means a test is stuck or waiting for user input'
      puts '   Check for permission dialogs or infinite loops'
      puts "   Tip: Use './Scripts/monitor_tests.sh' for more detailed monitoring"

      # Force kill on timeout
      system("pkill -9 -f 'xcodebuild test' 2>/dev/null")
      system('killall -9 xcodebuild 2>/dev/null')
      system('killall -9 SaneVideo 2>/dev/null')
      system("pkill -9 -f 'SaneVideo.*test' 2>/dev/null")
      system("pkill -9 -f 'grant_permissions' 2>/dev/null")
      system('killall -9 SaneVideo 2>/dev/null')
      system("pkill -9 -f 'SaneVideo.*test' 2>/dev/null")
    end

    duration = (Time.now - start_time).to_i
    print "\r" # Clear spinner

    # Ensure process is fully terminated
    sleep(0.5)
    system("pkill -9 -f 'xcodebuild test' 2>/dev/null")
    system('killall -9 SaneVideo 2>/dev/null')
    system("pkill -9 -f 'SaneVideo.*test' 2>/dev/null")
    system("pkill -9 -f 'grant_permissions' 2>/dev/null")

    {
      success: success && !timed_out,
      tests_run: tests_run,
      duration: duration,
      timeout: timed_out
    }
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
      puts '✅ Nuclear clean complete.'
    else
      puts 'Standard clean...'
      system('xcodebuild clean -scheme SaneVideo 2>&1 > /dev/null')
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
          context = content[start_idx..start_idx + 3000] || ''

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
    if ui_identifiers.count > 0
      coverage = (test_references.count.to_f / ui_identifiers.count * 100).round(1)
      puts "   Coverage: #{coverage}%"
    end
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
        if enum_content
          enum_content.scan(/static let #{match[0]} = ["']([^"']+)["']/) do |enum_match|
            identifiers << enum_match[0]
          end
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

    # 2. Export diagnostics
    export_path = File.join(@diagnostics_dir, "diagnostics_#{Time.now.strftime('%Y%m%d_%H%M%S')}")
    FileUtils.mkdir_p(export_path)

    export_cmd = "xcrun xcresulttool export --type directory --path '#{xcresult}' --output-path '#{export_path}' 2>&1"
    export_result = `#{export_cmd}`

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
    # Priority: 1. DerivedData logs (Agent workflow), 2. Fastlane output, 3. Tmp directory
    dd_logs = Dir.glob('.derivedData/Logs/Test/*.xcresult')
    fl_logs = Dir.glob('fastlane/test_output/*.xcresult')
    tmp_logs = Dir.glob('/tmp/*.xcresult')

    (dd_logs + fl_logs + tmp_logs).max_by { |f| File.mtime(f) }
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
    
    exit_code = $?.exitstatus
    
    if exit_code == 0
      puts ''
      puts '✅ No unused code detected!'
    else
      puts ''
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
    deprecation_warnings = build_output.lines.select { |line| 
      line.downcase.include?('deprecated') || 
      line.include?('was deprecated') ||
      line.include?('is deprecated')
    }.map(&:strip).reject(&:empty?).uniq

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
        file = File.basename($1)
        line = $2
        message = $4
        warnings_by_file[file] ||= []
        warnings_by_file[file] << { line: line, message: message }
      elsif warning.include?('warning:') && warning.include?('.swift')
        # Try alternative format
        parts = warning.split(':')
        if parts.length >= 4
          file = File.basename(parts[0])
          line = parts[1]
          message = parts[3..-1].join(':').strip
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
end

# Execute
SaneMaster.new.run(ARGV)
