#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Process Enforcer Hook
# ==============================================================================
# BLOCKS tool calls when Claude tries to bypass required processes.
# This is the "no shortcuts" enforcement layer.
#
# Enforces:
# 1. SaneLoop started when user requested it
# 2. Research done before using unfamiliar APIs
# 3. Plan shown for approval before implementation
# 4. Proper commit workflow (not just "git commit")
# 5. Bug logging to memory (not just mentioned)
# 6. Proper session summary format (not casual self-rating)
# 7. Verify cycle run before claiming "done"
#
# Hook Type: PreToolUse (Edit, Write, Bash)
# Exit 0 = Allow, Exit 1 = BLOCK
# ==============================================================================

require 'json'
require 'fileutils'

REQUIREMENTS_FILE = '.claude/prompt_requirements.json'
SANELOOP_STATE_FILE = '.claude/saneloop-state.json'
SATISFACTION_FILE = '.claude/process_satisfaction.json'
ENFORCEMENT_LOG = '.claude/enforcement_log.jsonl'

# ═══════════════════════════════════════════════════════════════════════════════
# SATISFACTION CHECKS - How to verify each requirement is met
# ═══════════════════════════════════════════════════════════════════════════════

def saneloop_active?
  return false unless File.exist?(SANELOOP_STATE_FILE)

  state = JSON.parse(File.read(SANELOOP_STATE_FILE), symbolize_names: true)
  state[:active] == true
rescue StandardError
  false
end

def load_satisfaction
  return {} unless File.exist?(SATISFACTION_FILE)

  JSON.parse(File.read(SATISFACTION_FILE), symbolize_names: true)
rescue StandardError
  {}
end

def save_satisfaction(sat)
  FileUtils.mkdir_p(File.dirname(SATISFACTION_FILE))
  File.write(SATISFACTION_FILE, JSON.pretty_generate(sat))
end

def mark_satisfied(requirement)
  sat = load_satisfaction
  sat[requirement.to_sym] = { satisfied_at: Time.now.iso8601 }
  save_satisfaction(sat)
end

def is_satisfied?(requirement)
  sat = load_satisfaction
  sat[requirement.to_sym] && sat[requirement.to_sym][:satisfied_at]
end

def log_enforcement(action, details)
  FileUtils.mkdir_p(File.dirname(ENFORCEMENT_LOG))
  entry = {
    timestamp: Time.now.iso8601,
    action: action,
    details: details
  }
  File.open(ENFORCEMENT_LOG, 'a') { |f| f.puts entry.to_json }
end

def load_requirements
  return { requested: [], satisfied: [], modifiers: [] } unless File.exist?(REQUIREMENTS_FILE)

  JSON.parse(File.read(REQUIREMENTS_FILE), symbolize_names: true)
rescue StandardError
  { requested: [], satisfied: [], modifiers: [] }
end

# ═══════════════════════════════════════════════════════════════════════════════
# SHORTCUT DETECTION - Catch Claude trying to bypass
# ═══════════════════════════════════════════════════════════════════════════════

def detect_casual_self_rating(content)
  # Catch patterns like "Self-Rating: 8/10" or "Rating: 7/10" without proper format
  casual_patterns = [
    %r{Self-Rating:\s*\d+/10}i,
    %r{Rating:\s*\d+/10}i,
    %r{\*\*Self-rating:\s*\d+/10\*\*}i,
    %r{My rating:\s*\d+/10}i
  ]

  proper_format = content.include?('SOP Compliance:') && content.include?('Performance:')

  casual_patterns.any? { |p| content.match?(p) } && !proper_format
end

def detect_lazy_commit(command)
  # Catch simple "git commit" without full workflow
  return false unless command.match?(/git commit/i)

  # Full workflow should include: status, diff, add
  has_status = command.include?('status')
  has_diff = command.include?('diff')
  command.include?('add')

  # If it's just "git commit -m" without the workflow, it's lazy
  command.match?(/git commit\s+-m/i) && !has_status && !has_diff
end

def detect_skipped_verification(content, _tool_name)
  # Catch "done" claims without running verify
  done_patterns = [
    /\bdone\b/i,
    /\bcomplete\b/i,
    /\bfinished\b/i,
    /\ball set\b/i,
    /\bthat'?s it\b/i
  ]

  return false unless done_patterns.any? { |p| content.match?(p) }

  # Check if verify was run recently (within last 5 tool calls)
  return false unless File.exist?('.claude/audit.jsonl')

  recent_calls = File.readlines('.claude/audit.jsonl').last(10)
  recent_calls.any? { |line| line.include?('verify') || line.include?('qa.rb') }
rescue StandardError
  false
end

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN ENFORCEMENT LOGIC
# ═══════════════════════════════════════════════════════════════════════════════

begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0
end

tool_name = input['tool_name'] || ''
tool_input = input['tool_input'] || {}

# Get the content being written/edited
content = tool_input['new_string'] || tool_input['content'] || tool_input['command'] || ''
tool_input['file_path'] || ''

# Load requirements set by prompt_analyzer
reqs = load_requirements
requested = reqs[:requested] || []

blocks = []

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 1: SaneLoop Required
# ═══════════════════════════════════════════════════════════════════════════════

if requested.include?('saneloop') && !saneloop_active?
  blocks << {
    rule: 'SANELOOP_REQUIRED',
    message: 'User requested SaneLoop but none is active.',
    fix: 'Run: ./Scripts/SaneMaster.rb saneloop start "task" --criteria "..." --promise "..."'
  }
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 2: Research Required Before Implementation
# ═══════════════════════════════════════════════════════════════════════════════

if requested.include?('research') && !is_satisfied?(:research)
  # Allow Read, Grep, Glob, WebFetch, WebSearch, mcp__* tools - these ARE research
  research_tools = %w[Read Grep Glob WebFetch WebSearch Task]
  is_research_tool = research_tools.include?(tool_name) || tool_name.start_with?('mcp__')

  unless is_research_tool
    blocks << {
      rule: 'RESEARCH_FIRST',
      message: 'User requested research before implementation.',
      fix: 'Do research first (Read, Grep, WebSearch, apple-docs, context7), then mark satisfied.'
    }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 3: Plan Approval Required
# ═══════════════════════════════════════════════════════════════════════════════

# Block Edit/Write until plan is shown and approved
if requested.include?('plan') && !is_satisfied?(:plan) && %w[Edit Write].include?(tool_name)
  blocks << {
    rule: 'PLAN_APPROVAL_REQUIRED',
    message: 'User requested a plan before implementation.',
    fix: 'Show the plan in plain english for user approval first. Do NOT just reference a file.'
  }
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 4: Casual Self-Rating Detection
# ═══════════════════════════════════════════════════════════════════════════════

if %w[Edit Write].include?(tool_name) && detect_casual_self_rating(content)
  blocks << {
    rule: 'PROPER_RATING_FORMAT',
    message: 'Detected casual self-rating without proper format.',
    fix: 'Use: SOP Compliance: X/10 (auto from compliance report) + Performance: X/10 (with gaps)'
  }
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 5: Lazy Commit Detection
# ═══════════════════════════════════════════════════════════════════════════════

if tool_name == 'Bash' && detect_lazy_commit(content)
  blocks << {
    rule: 'FULL_COMMIT_WORKFLOW',
    message: 'Detected simple "git commit" without full workflow.',
    fix: 'Full workflow: git pull → status → diff → add → commit (with README update if needed)'
  }
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 6: Bug Note Must Update Memory
# ═══════════════════════════════════════════════════════════════════════════════

# If not using memory MCP, block
# Allow research tools, but block implementation until memory is updated
if requested.include?('bug_note') && !is_satisfied?(:bug_note) && !tool_name.start_with?('mcp__memory') && %w[Edit Write Bash].include?(tool_name)
  blocks << {
    rule: 'BUG_TO_MEMORY',
    message: 'Bug note requested but memory not updated.',
    fix: 'Use mcp__memory__create_entities or mcp__memory__add_observations to log the bug pattern.'
  }
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 7: Verify Before Done
# ═══════════════════════════════════════════════════════════════════════════════

# Check if claiming done without verification
if requested.include?('verify') && !is_satisfied?(:verify) && %w[Edit Write].include?(tool_name) && content.match?(/\b(done|complete|finished)\b/i)
  # Check recent audit log for verify/qa.rb
  verified_recently = false
  if File.exist?('.claude/audit.jsonl')
    recent = File.readlines('.claude/audit.jsonl').last(20).join
    verified_recently = recent.include?('verify') || recent.include?('qa.rb')
  end

  unless verified_recently
    blocks << {
      rule: 'VERIFY_BEFORE_DONE',
      message: 'Claiming "done" but verification not run.',
      fix: 'Run: ./Scripts/SaneMaster.rb verify (or ruby scripts/qa.rb) before claiming done.'
    }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# ENFORCEMENT OUTPUT
# ═══════════════════════════════════════════════════════════════════════════════

if blocks.any?
  log_enforcement('BLOCKED', blocks.map { |b| b[:rule] })

  warn ''
  warn '═══════════════════════════════════════════════════════════════'
  warn '  🛑 PROCESS VIOLATION - TOOL CALL BLOCKED'
  warn '═══════════════════════════════════════════════════════════════'
  warn ''

  blocks.each do |b|
    warn "  ❌ #{b[:rule]}"
    warn "     #{b[:message]}"
    warn "     → #{b[:fix]}"
    warn ''
  end

  warn '  This block exists because you are trying to bypass a required process.'
  warn '  Complete the required steps first, or ask user to override.'
  warn ''
  warn '═══════════════════════════════════════════════════════════════'
  warn ''

  exit 1 # BLOCK THE TOOL CALL
end

# ═══════════════════════════════════════════════════════════════════════════════
# AUTO-SATISFACTION DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

# If this is a research tool and research was required, mark as progressing
if requested.include?('research') && (tool_name.start_with?('mcp__') || %w[Read Grep WebSearch WebFetch].include?(tool_name))
  # After 3 research operations, consider it satisfied
  log_enforcement('RESEARCH_PROGRESS', tool_name)
end

# If using memory MCP for bug, mark satisfied
if requested.include?('bug_note') && tool_name.start_with?('mcp__memory')
  mark_satisfied(:bug_note)
  log_enforcement('SATISFIED', 'bug_note via memory MCP')
end

exit 0
