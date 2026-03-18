#!/usr/bin/env python3
"""Generate a larger SaneVideo workflow-planning corpus.

The goal is to train SaneAI on the actual workflow JSON contract that
SaneVideo expects, while also teaching the model to resist the legacy
`{"operations": ...}` schema for transcript-grounded workflow requests.
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).parent
TRAIN_PATH = ROOT / "train.jsonl"
VALID_PATH = ROOT / "valid.jsonl"
PLACEHOLDER = "PLACEHOLDER_SYSTEM_PROMPT"


def seconds(raw: str) -> float:
    parts = [int(part) for part in raw.split(":")]
    if len(parts) == 2:
        return float(parts[0] * 60 + parts[1])
    if len(parts) == 3:
        return float(parts[0] * 3600 + parts[1] * 60 + parts[2])
    raise ValueError(f"Bad timestamp: {raw}")


def line(ts: str, text: str) -> tuple[str, str]:
    return ts, text


def item(concept: str, claim: str, refs: str, excerpt: str, start: str, end: str, confidence: float) -> dict:
    return {
        "concept": concept,
        "claim": claim,
        "supportingReferences": refs,
        "sourceExcerpt": excerpt,
        "startTime": seconds(start),
        "endTime": seconds(end),
        "confidence": confidence,
    }


SCENARIOS = [
    {
        "workflow": "commentary",
        "instructions": "Explain why the call centers optics over substance and include supporting references.",
        "voice": "Keep the focus on truth, repentance, and qualification, not on whether the exposure looked awkward.",
        "max": 1,
        "transcript": [
            line("02:28", "Not so much the accusations."),
            line("04:53", "The issue is how it was handled."),
            line("05:29", "It was the way this was brought out."),
        ],
        "summary": "The speaker shifts the center of gravity from whether the allegations are true to whether they were surfaced publicly.",
        "items": [
            item(
                "Optics Over Substance",
                "The call frames the main problem as the handling of the accusations instead of the truth, repentance, and qualification questions underneath them.",
                "1 Timothy 3:1-7; Titus 1:5-9; James 3:1; 1 Timothy 5:19-21",
                "Not so much the accusations. The issue is how it was handled.",
                "02:28",
                "05:29",
                0.95,
            )
        ],
    },
    {
        "workflow": "commentary",
        "instructions": "Show why private reconciliation texts do not erase public accountability for leaders and include supporting references.",
        "voice": "Make the distinction cleanly: private peacemaking matters, but public leaders still face public accountability.",
        "max": 1,
        "transcript": [
            line("10:49", "If you have ought with your brother, go to your brother."),
            line("11:58", "We need to follow Matthew 5."),
            line("18:41", "I owe him a debt of love to go to him first."),
            line("19:01", "That's how I would handle it."),
        ],
        "summary": "The speakers lean on private reconciliation texts, but those passages do not cancel public accountability for public leaders.",
        "items": [
            item(
                "Private Texts, Public Leaders",
                "The call treats a public-leader issue mainly as a private relational dispute, even though elders and teachers are also judged under public-accountability texts.",
                "Matthew 18:15; 1 Timothy 5:19-21; Galatians 2:11-14",
                "If you have ought with your brother, go to your brother. We need to follow Matthew 5.",
                "10:49",
                "19:01",
                0.93,
            )
        ],
    },
    {
        "workflow": "commentary",
        "instructions": "Explain how the speakers framed the issue as old and settled. Include supporting references.",
        "voice": "Keep the claim narrow and grounded in the timestamps. Show how the age framing softens the force of the allegations.",
        "max": 1,
        "transcript": [
            line("15:15", "None of this stuff is new."),
            line("15:18", "All this stuff goes back years."),
            line("15:21", "When Jeremiah was in his 20s and early 30s was most of it."),
            line("35:52", "This was sloppy prophecy from his earlier years."),
        ],
        "summary": "The call repeatedly presents the controversy as old material from earlier years, which makes it sound settled and distant.",
        "items": [
            item(
                "Old-Issue Framing",
                "The room keeps describing the concerns as old and already answered instead of showing why the evidence should be treated as closed.",
                "Acts 17:11; 1 Thessalonians 5:21",
                "None of this stuff is new. All this stuff goes back years.",
                "15:15",
                "35:52",
                0.9,
            )
        ],
    },
    {
        "workflow": "commentary",
        "instructions": "Show why reputational fallout is not the main biblical center of gravity. Include supporting references.",
        "voice": "The point is not that collateral damage is fake. The point is that the flock still has to come first.",
        "max": 1,
        "transcript": [
            line("06:50", "This affects his wife, his family, his church, and his ministry."),
            line("07:03", "There is collateral damage here."),
            line("12:44", "This affects churches and ministries."),
            line("13:15", "This has had ripple effects."),
        ],
        "summary": "The call spends emotional energy on the fallout, but biblical leadership still centers protecting the flock and handling truth clearly.",
        "items": [
            item(
                "Fallout Versus Flock Protection",
                "The call emphasizes collateral damage and ripple effects, but shepherds are first responsible to protect the flock and uphold truth.",
                "Acts 20:28-31",
                "This affects his wife, his family, his church, and his ministry. There is collateral damage here.",
                "06:50",
                "13:15",
                0.92,
            )
        ],
    },
    {
        "workflow": "commentary",
        "instructions": "Show how insider reassurance replaced transparent testing. Include supporting references.",
        "voice": "Point out that private vetting may explain a conclusion, but it does not substitute for showing the work.",
        "max": 1,
        "transcript": [
            line("20:47", "Jeremiah's fruit here has been impeccable."),
            line("31:11", "There's no unrepentant or repeated sin that you see."),
            line("32:19", "He publicly owned that past failure."),
            line("36:34", "He has repented."),
        ],
        "summary": "The audience is asked to trust insider judgment rather than watch the leaders carefully test the matter in public.",
        "items": [
            item(
                "Private Vetting, Public Trust-Me",
                "The speakers rely on private reassurances and internal conclusions instead of showing how the claims were tested.",
                "Acts 17:11; 1 Thessalonians 5:21; 1 Timothy 5:19-21",
                "Jeremiah's fruit here has been impeccable. He has repented.",
                "20:47",
                "36:34",
                0.91,
            )
        ],
    },
    {
        "workflow": "commentary",
        "instructions": "Trace the inconsistency on motive-reading. Include supporting references.",
        "voice": "Keep it simple: they tell the room not to judge motives, then they do it anyway.",
        "max": 1,
        "transcript": [
            line("23:15", "Maybe he was afraid. Maybe he wanted clicks."),
            line("35:03", "We need to be very careful not to assign motive."),
            line("35:21", "Only God sees motive clearly."),
        ],
        "summary": "The call warns against reading motives while also floating motive theories of its own.",
        "items": [
            item(
                "Motive Standard Applied Unevenly",
                "The room tells listeners not to assign motives, but it still frames the absent side with speculative motives like fear and click-chasing.",
                "1 Corinthians 4:5",
                "Maybe he was afraid. Maybe he wanted clicks. We need to be very careful not to assign motive.",
                "23:15",
                "35:21",
                0.89,
            )
        ],
    },
    {
        "workflow": "commentary",
        "instructions": "Show how the call sounded impartial but steered pastors toward distancing Jake. Include supporting references.",
        "voice": "Use the sequence of the room: permission language first, narrowing language after.",
        "max": 1,
        "transcript": [
            line("24:04", "Should we pause having Jake in our churches?"),
            line("24:52", "You can make up your own minds."),
            line("26:34", "We can't both be right."),
            line("27:14", "I do not have ministerial confidence to have him back."),
        ],
        "summary": "The meeting presents itself as open-handed at first, then narrows the acceptable conclusion toward distancing Jake from ministerial trust.",
        "items": [
            item(
                "Impartial Language, Guided Outcome",
                "The speakers say pastors can decide for themselves, but the room is steered toward withdrawing ministerial confidence from Jake.",
                "Proverbs 18:17; 1 Timothy 5:21; Leviticus 19:15",
                "You can make up your own minds. We can't both be right. I do not have ministerial confidence to have him back.",
                "24:04",
                "27:14",
                0.94,
            )
        ],
    },
    {
        "workflow": "commentary",
        "instructions": "Distinguish repentance from qualification and include supporting references.",
        "voice": "The key is mercy without collapsing the leadership question.",
        "max": 1,
        "transcript": [
            line("32:19", "He publicly owned that past failure."),
            line("36:34", "He has repented."),
            line("41:19", "One failure is not automatic disqualification."),
            line("42:19", "I want to err on the side of mercy."),
        ],
        "summary": "The careful frame keeps repentance and mercy in view while still asking the separate question of qualification for public ministry.",
        "items": [
            item(
                "Repentance Is Not The Whole Question",
                "The call treats repentance as nearly decisive, but a biblical evaluation still has to ask whether public qualification remains intact.",
                "Matthew 3:8; 2 Corinthians 7:10-11; 1 Timothy 3:1-7; Titus 1:5-9",
                "He publicly owned that past failure. He has repented. One failure is not automatic disqualification.",
                "32:19",
                "42:19",
                0.93,
            )
        ],
    },
    {
        "workflow": "commentary",
        "instructions": "Explain why mercy and restoration do not automatically answer the platform question. Include supporting references.",
        "voice": "A forgiven brother and a trusted public teacher are related but not identical categories.",
        "max": 1,
        "transcript": [
            line("41:48", "Think about Peter and David."),
            line("42:32", "God restores people."),
            line("43:11", "I want to err on the side of mercy."),
        ],
        "summary": "The appeal to Peter, David, and mercy is true as far as it goes, but it does not automatically settle timing or trust for public ministry.",
        "items": [
            item(
                "Grace Does Not Equal Immediate Platform Trust",
                "The call rightly highlights mercy, but restoration to fellowship is not identical to immediate restoration to public platform and trust.",
                "Galatians 6:1; 1 Timothy 3:1-7; Titus 1:5-9",
                "Think about Peter and David. God restores people.",
                "41:48",
                "43:11",
                0.9,
            )
        ],
    },
    {
        "workflow": "commentary",
        "instructions": "Explain why the main question for a public teacher is qualification, not embarrassment. No verse references on this pass.",
        "voice": "Keep the tone analytical and leave supportingReferences empty.",
        "max": 1,
        "transcript": [
            line("04:46", "The issue is how it was handled."),
            line("05:11", "The accusations themselves are not the central point for me."),
            line("07:03", "There is collateral damage here."),
        ],
        "summary": "The call keeps pulling the focus toward tone and embarrassment, even though the ministerial question is fundamentally about qualification.",
        "items": [
            item(
                "Public Qualification Is The Main Question",
                "The framing keeps moving toward tone and fallout instead of staying on whether a public teacher remains qualified.",
                "",
                "The issue is how it was handled. The accusations themselves are not the central point for me.",
                "04:46",
                "07:03",
                0.88,
            )
        ],
    },
    {
        "workflow": "meetingReview",
        "instructions": "Pull out the biggest decision, the main disagreement, and the clearest action item.",
        "voice": "This should read like a SaneVideo review card, not meeting minutes.",
        "max": 3,
        "transcript": [
            line("00:18", "We need to choose between shipping commentary flow Friday or fixing source timestamps first."),
            line("00:42", "Marketing wants Friday because the launch email is already drafted."),
            line("01:03", "Engineering says missing source timestamps makes the reel impossible to audit."),
            line("01:28", "Decision: hold the release until source timestamps show in every clip."),
            line("01:44", "Action item: Maya owns the timestamp overlay fix and preview by tomorrow noon."),
        ],
        "summary": "The team delays the launch because timestamp visibility is treated as a product requirement, not a nice-to-have.",
        "items": [
            item("Release Decision", "The release is delayed until source timestamps appear in every clip.", "Decision", "Decision: hold the release until source timestamps show in every clip.", "01:28", "01:35", 0.96),
            item("Main Disagreement", "Marketing pushes for the Friday send while engineering argues the missing timestamps break auditability.", "Disagreement", "Marketing wants Friday... Engineering says missing source timestamps makes the reel impossible to audit.", "00:42", "01:17", 0.9),
            item("Action Item", "Maya owns the timestamp overlay fix and preview for tomorrow noon.", "Action item", "Action item: Maya owns the timestamp overlay fix and preview by tomorrow noon.", "01:44", "01:52", 0.97),
        ],
    },
    {
        "workflow": "meetingReview",
        "instructions": "Extract the decision and the next two actions.",
        "voice": "Focus on rollout control and what happens next.",
        "max": 3,
        "transcript": [
            line("00:09", "Support wants to pause the export rollout until the overlay bug is fixed."),
            line("00:27", "Product wants to keep ten percent of creators on the new build for signal."),
            line("00:46", "Decision: freeze the wider rollout and keep the ten percent cohort only."),
            line("01:02", "Action: Ava writes the customer note."),
            line("01:10", "Action: Marco ships the overlay fix candidate by 4 PM."),
        ],
        "summary": "The team narrows the rollout, keeps a small cohort on the new export, and assigns two immediate follow-ups.",
        "items": [
            item("Decision", "The wider rollout is frozen while the ten percent cohort stays on the new build.", "Decision", "Decision: freeze the wider rollout and keep the ten percent cohort only.", "00:46", "00:55", 0.96),
            item("Customer Note", "Ava owns the customer-facing note about the rollout pause.", "Action item", "Action: Ava writes the customer note.", "01:02", "01:06", 0.94),
            item("Fix Candidate", "Marco owns the overlay fix candidate for the 4 PM check-in.", "Action item", "Action: Marco ships the overlay fix candidate by 4 PM.", "01:10", "01:18", 0.95),
        ],
    },
    {
        "workflow": "meetingReview",
        "instructions": "Summarize the decision, the technical blocker, and who owns the follow-up.",
        "voice": "This one is about the mini training lane and why serial evaluation won.",
        "max": 3,
        "transcript": [
            line("00:14", "Running two evals at once keeps blowing the mini out of memory."),
            line("00:31", "If we stay parallel, the nightly score is noisy and half the runs die."),
            line("00:52", "Decision: keep the eval lane serial on the 8 GB mini."),
            line("01:06", "Nina owns the scheduler patch and report update."),
        ],
        "summary": "The team accepts a slower but deterministic serial eval lane because the mini cannot sustain parallel model runs reliably.",
        "items": [
            item("Decision", "The nightly eval lane stays serial on the 8 GB mini.", "Decision", "Decision: keep the eval lane serial on the 8 GB mini.", "00:52", "01:00", 0.95),
            item("Technical Blocker", "Parallel evals are causing repeat OOM failures and noisy nightly results.", "Blocker", "Running two evals at once keeps blowing the mini out of memory.", "00:14", "00:40", 0.92),
            item("Owner", "Nina owns the scheduler patch and the nightly report update.", "Action item", "Nina owns the scheduler patch and report update.", "01:06", "01:12", 0.94),
        ],
    },
    {
        "workflow": "meetingReview",
        "instructions": "Pull the principle decision, the main debate, and the implementation owner.",
        "voice": "This discussion is about using Prakeet for the brief while keeping the transcript as evidence.",
        "max": 3,
        "transcript": [
            line("00:11", "Voice notes are great for intent, but they should not become the evidence source."),
            line("00:29", "Somebody asks whether the AI should be allowed to infer missing facts from the voice brief."),
            line("00:47", "Decision: the transcript remains the ground truth and the voice brief only sets focus."),
            line("01:03", "Jared owns the brief UI copy and schema docs."),
        ],
        "summary": "The meeting draws a hard line between user intent and evidence so the product stays grounded in the transcript.",
        "items": [
            item("Principle Decision", "The transcript stays the ground truth while the voice brief only sets focus.", "Decision", "Decision: the transcript remains the ground truth and the voice brief only sets focus.", "00:47", "00:58", 0.96),
            item("Main Debate", "The room debates whether the AI may infer missing facts from the user's voice brief.", "Debate", "Somebody asks whether the AI should be allowed to infer missing facts from the voice brief.", "00:29", "00:42", 0.89),
            item("Owner", "Jared owns the brief UI copy and schema docs.", "Action item", "Jared owns the brief UI copy and schema docs.", "01:03", "01:09", 0.94),
        ],
    },
    {
        "workflow": "meetingReview",
        "instructions": "Extract the release decision, the quality threshold, and the next check.",
        "voice": "Make the QA threshold explicit.",
        "max": 3,
        "transcript": [
            line("00:08", "I do not want to ship this until the subtitles stay inside frame on the exported MP4."),
            line("00:25", "Preview accuracy is not enough. We need real frame grabs from the output file."),
            line("00:43", "Decision: export five worst-case frames before every release candidate."),
            line("01:02", "Next check: tomorrow morning after the vertical layout patch lands."),
        ],
        "summary": "The team turns rendered-frame inspection into a release requirement instead of trusting the preview alone.",
        "items": [
            item("Release Decision", "Every release candidate now requires worst-case frame grabs from the exported MP4.", "Decision", "Decision: export five worst-case frames before every release candidate.", "00:43", "00:52", 0.95),
            item("Quality Threshold", "Preview correctness is not enough; the team wants proof from real exported frames.", "Threshold", "Preview accuracy is not enough. We need real frame grabs from the output file.", "00:25", "00:39", 0.92),
            item("Next Check", "The next QA pass happens tomorrow after the vertical layout patch lands.", "Next check", "Next check: tomorrow morning after the vertical layout patch lands.", "01:02", "01:09", 0.91),
        ],
    },
    {
        "workflow": "salesCoach",
        "instructions": "Find the strongest objection, the best recovery moment, and one coach-up opportunity.",
        "voice": "This is an enterprise privacy call, so anchor the analysis around trust and procurement.",
        "max": 3,
        "transcript": [
            line("00:15", "This sounds expensive compared to doing it manually."),
            line("00:34", "The rep says the workflow saves each manager six hours a week."),
            line("00:54", "The buyer asks whether customer recordings ever leave their environment."),
            line("01:10", "The rep says everything stays local and can run without cloud telemetry."),
            line("01:28", "The rep keeps talking after the buyer says privacy is the real blocker."),
        ],
        "summary": "Privacy is the real buying issue, and the rep partially answers it but misses the chance to close around that concern.",
        "items": [
            item("Strongest Objection", "The buyer's strongest objection is privacy, not price, because they focus on whether recordings ever leave their environment.", "Objection", "The buyer asks whether customer recordings ever leave their environment.", "00:54", "01:02", 0.94),
            item("Best Recovery", "The rep recovers well by saying the workflow stays local and can run without cloud telemetry.", "Strong moment", "The rep says everything stays local and can run without cloud telemetry.", "01:10", "01:18", 0.91),
            item("Coach-Up", "The rep should stop talking past the buyer and tighten the close around privacy once the blocker is named.", "Coach-up", "The rep keeps talking after the buyer says privacy is the real blocker.", "01:28", "01:36", 0.88),
        ],
    },
    {
        "workflow": "salesCoach",
        "instructions": "Surface the main objection, the clearest trust-builder, and the missed close.",
        "voice": "Use the timestamps and keep the language short enough for a coaching card.",
        "max": 3,
        "transcript": [
            line("00:12", "I can't take a cloud model into customer support calls."),
            line("00:30", "The rep explains that the entire edit and transcript stack can run on device."),
            line("00:46", "The buyer asks whether the model is trained on customer footage."),
            line("01:01", "The rep says no training happens on customer footage and the data never leaves the Mac."),
            line("01:17", "The rep never asks for the pilot after getting agreement on privacy."),
        ],
        "summary": "The rep handles the trust question well but fails to convert that trust into a concrete next step.",
        "items": [
            item("Main Objection", "The buyer's main objection is taking cloud tooling into sensitive support calls.", "Objection", "I can't take a cloud model into customer support calls.", "00:12", "00:20", 0.93),
            item("Trust Builder", "The rep builds trust by clearly saying no customer footage is used for training and the data stays on the Mac.", "Strong moment", "No training happens on customer footage and the data never leaves the Mac.", "00:46", "01:08", 0.92),
            item("Missed Close", "The rep should ask for the pilot after the privacy concern is resolved instead of letting the momentum fade.", "Coach-up", "The rep never asks for the pilot after getting agreement on privacy.", "01:17", "01:25", 0.87),
        ],
    },
    {
        "workflow": "salesCoach",
        "instructions": "Find the objection, the strongest value moment, and a coach-up note.",
        "voice": "This one is about creators who think the current process is already good enough.",
        "max": 3,
        "transcript": [
            line("00:10", "We already have an editor clipping the show by hand."),
            line("00:27", "The rep says grouped concepts plus transcript grounding cut two review rounds."),
            line("00:45", "The buyer asks whether the AI ever invents claims that were not in the source."),
            line("01:04", "The rep says each card points back to timestamps and stays editable before export."),
            line("01:23", "The rep never contrasts that against the buyer's current revision pain."),
        ],
        "summary": "The rep answers the hallucination risk well but underplays the specific operational pain the workflow removes.",
        "items": [
            item("Objection", "The buyer thinks the manual workflow is already acceptable because they already have an editor clipping by hand.", "Objection", "We already have an editor clipping the show by hand.", "00:10", "00:18", 0.9),
            item("Strongest Value Moment", "The rep's strongest value case is that grouped concepts and transcript grounding remove two rounds of review.", "Strong moment", "Grouped concepts plus transcript grounding cut two review rounds.", "00:27", "00:36", 0.91),
            item("Coach-Up", "The rep should tie the source-grounding answer back to the buyer's revision pain instead of leaving the comparison implicit.", "Coach-up", "The rep never contrasts that against the buyer's current revision pain.", "01:23", "01:31", 0.86),
        ],
    },
    {
        "workflow": "salesCoach",
        "instructions": "Pull the real blocker, the best answer, and one thing the rep should do next time.",
        "voice": "Emphasize auditability and compliance, not price.",
        "max": 3,
        "transcript": [
            line("00:14", "Legal will ask me how I know this clip summary matches the source."),
            line("00:31", "The rep says every concept card keeps the original timestamps and excerpt."),
            line("00:47", "The buyer says that's the first answer that sounds auditable."),
            line("01:05", "The rep changes the topic instead of digging into legal review."),
        ],
        "summary": "The rep uncovers a compliance blocker and answers it well, but misses the chance to deepen the legal-review path.",
        "items": [
            item("Real Blocker", "The actual blocker is legal auditability, not general curiosity about AI.", "Objection", "Legal will ask me how I know this clip summary matches the source.", "00:14", "00:23", 0.93),
            item("Best Answer", "The strongest answer is that each concept card carries the original timestamps and source excerpt.", "Strong moment", "Every concept card keeps the original timestamps and excerpt.", "00:31", "00:39", 0.92),
            item("Coach-Up", "The rep should stay on the legal-review thread after the buyer signals that auditability matters.", "Coach-up", "The rep changes the topic instead of digging into legal review.", "01:05", "01:13", 0.88),
        ],
    },
    {
        "workflow": "salesCoach",
        "instructions": "Highlight the strongest objection, best recovery, and missed follow-up.",
        "voice": "This customer cares about keyboard accessibility as part of procurement.",
        "max": 3,
        "transcript": [
            line("00:11", "If this can't be driven by keyboard, my team won't adopt it."),
            line("00:27", "The rep says every major edit step can be triggered without touching the mouse."),
            line("00:43", "The buyer asks whether export QA also stays keyboard-friendly."),
            line("00:58", "The rep says the frame-review workflow still needs some polish there."),
            line("01:12", "The rep never offers to show the current keyboard path live."),
        ],
        "summary": "The rep handles the accessibility requirement honestly, but misses the strongest trust move: a live keyboard walkthrough.",
        "items": [
            item("Strongest Objection", "Keyboard accessibility is a hard adoption requirement for the buyer's team.", "Objection", "If this can't be driven by keyboard, my team won't adopt it.", "00:11", "00:19", 0.93),
            item("Best Recovery", "The rep builds trust by clearly saying the major edit path is already keyboard-driven.", "Strong moment", "Every major edit step can be triggered without touching the mouse.", "00:27", "00:36", 0.89),
            item("Missed Follow-Up", "The rep should offer a live keyboard walkthrough instead of leaving the buyer with an abstract promise.", "Coach-up", "The rep never offers to show the current keyboard path live.", "01:12", "01:19", 0.87),
        ],
    },
    {
        "workflow": "teachingStudy",
        "instructions": "Group this teaching into study-ready ideas with concise supporting references.",
        "voice": "Keep the concepts crisp and suitable for chapter cards.",
        "max": 2,
        "transcript": [
            line("00:08", "Grace restores sinners."),
            line("00:24", "Leadership still carries qualifications."),
            line("00:43", "Restoration and qualification are related, but they are not identical."),
            line("01:02", "That is why mercy should not erase discernment."),
        ],
        "summary": "The teaching separates personal restoration from public qualification so listeners can study both without collapsing them into one category.",
        "items": [
            item("Grace Restores", "Grace restores sinners and keeps mercy central.", "Galatians 6:1", "Grace restores sinners.", "00:08", "00:15", 0.9),
            item("Qualification Still Matters", "Public leadership still has qualifications, so mercy should not erase discernment.", "1 Timothy 3:1-7; Titus 1:5-9", "Leadership still carries qualifications. Restoration and qualification are related, but they are not identical.", "00:24", "01:02", 0.95),
        ],
    },
    {
        "workflow": "teachingStudy",
        "instructions": "Turn this into grouped study ideas. Include references only where the transcript clearly asks for them.",
        "voice": "This is about transcript grounding and human review.",
        "max": 3,
        "transcript": [
            line("00:07", "The transcript is the evidence source."),
            line("00:23", "The brief tells the AI what to focus on, not what happened."),
            line("00:40", "That is why human review still sits before export."),
        ],
        "summary": "The lesson teaches a simple order: evidence from the transcript, focus from the brief, and review before export.",
        "items": [
            item("Transcript As Evidence", "The transcript is the evidence source for every planned clip.", "", "The transcript is the evidence source.", "00:07", "00:14", 0.93),
            item("Brief Sets Focus", "The brief is for emphasis and intent, not for inventing facts that were never said.", "", "The brief tells the AI what to focus on, not what happened.", "00:23", "00:31", 0.92),
            item("Review Before Export", "Human review remains part of the workflow before anything is exported.", "", "That is why human review still sits before export.", "00:40", "00:47", 0.9),
        ],
    },
    {
        "workflow": "teachingStudy",
        "instructions": "Build study-ready themes around privacy and trust.",
        "voice": "Make this useful for an internal enablement video.",
        "max": 2,
        "transcript": [
            line("00:09", "Privacy is not just branding. It is procurement."),
            line("00:27", "Sensitive teams buy trust before they buy features."),
            line("00:45", "That is why local-first architecture changes the sales conversation."),
        ],
        "summary": "The teaching shows why privacy-first design is more than a slogan: it changes whether certain teams can buy at all.",
        "items": [
            item("Privacy As Procurement", "Privacy matters because it determines whether risk-sensitive teams can even consider the tool.", "", "Privacy is not just branding. It is procurement.", "00:09", "00:19", 0.92),
            item("Trust Changes The Sale", "Local-first architecture changes the sales conversation because trust comes before features for sensitive teams.", "", "Sensitive teams buy trust before they buy features. That is why local-first architecture changes the sales conversation.", "00:27", "00:45", 0.93),
        ],
    },
    {
        "workflow": "teachingStudy",
        "instructions": "Turn this into grouped teaching moments about QA discipline.",
        "voice": "Keep the supporting references empty and stay product-specific.",
        "max": 2,
        "transcript": [
            line("00:11", "Preview accuracy is not the same as export accuracy."),
            line("00:28", "Rendered frames are the proof."),
            line("00:44", "That is how you keep overlays inside the safe area instead of hoping."),
        ],
        "summary": "The lesson turns export QA into a discipline: trust the rendered frames, not the preview alone.",
        "items": [
            item("Rendered Output Is The Proof", "Preview correctness still has to be confirmed against the real exported file.", "", "Preview accuracy is not the same as export accuracy. Rendered frames are the proof.", "00:11", "00:34", 0.94),
            item("QA Beats Hope", "Safe-area bugs are prevented by checking frames, not by assuming the layout will hold.", "", "That is how you keep overlays inside the safe area instead of hoping.", "00:44", "00:52", 0.9),
        ],
    },
    {
        "workflow": "teachingStudy",
        "instructions": "Group these ideas into study-ready sections with short references.",
        "voice": "This one is about workflow scoring and why raw accuracy can mislead you.",
        "max": 2,
        "transcript": [
            line("00:10", "A model can look strong on the old action tests and still fail the new workflow job."),
            line("00:30", "That is why the workflow gate matters more than a flattering raw score."),
            line("00:49", "A benchmark that rewards the wrong shape will teach the wrong behavior."),
        ],
        "summary": "The teaching explains why the evaluation harness has to reward the job you actually want, not the behavior the older app trained hardest.",
        "items": [
            item("Workflow Gate Over Raw Score", "A good-looking raw score is not enough if the model still fails the workflow task it now needs to perform.", "", "A model can look strong on the old action tests and still fail the new workflow job.", "00:10", "00:38", 0.94),
            item("Benchmarks Shape Behavior", "If the benchmark rewards the wrong output shape, the model will keep learning the wrong behavior.", "", "A benchmark that rewards the wrong shape will teach the wrong behavior.", "00:49", "00:58", 0.91),
        ],
    },
    {
        "workflow": "supportQA",
        "instructions": "Surface the bug moment, the reproduction path, and the user impact.",
        "voice": "Use the exact import-sheet failure, not a generic modal bug.",
        "max": 3,
        "transcript": [
            line("00:05", "I press Command-I to import the video."),
            line("00:12", "The import sheet opens, but then another file picker tries to open on top of it."),
            line("00:24", "The app gets stuck and I cannot close the modal cleanly."),
            line("00:39", "I have to force quit before I can keep working."),
        ],
        "summary": "The bug is a nested import flow that traps the user inside a stuck modal and forces a quit.",
        "items": [
            item("Bug Moment", "A second file picker opens on top of the import sheet and creates the visible failure.", "Bug moment", "Another file picker tries to open on top of it.", "00:12", "00:18", 0.95),
            item("Reproduction Path", "Press Command-I, trigger import, and the nested picker flow reproduces the stuck modal.", "Repro", "I press Command-I to import the video. The import sheet opens.", "00:05", "00:18", 0.92),
            item("User Impact", "The user gets trapped in the modal and has to force quit before they can continue working.", "Impact", "The app gets stuck and I cannot close the modal cleanly. I have to force quit.", "00:24", "00:39", 0.96),
        ],
    },
    {
        "workflow": "supportQA",
        "instructions": "Pull the bug moment, user impact, and the clearest visual symptom.",
        "voice": "This is the exported-overlay regression, not an editor-preview bug.",
        "max": 3,
        "transcript": [
            line("00:08", "The commentary overlay is visible in the editor preview."),
            line("00:21", "After export, the MP4 shows the clip but the commentary card is gone."),
            line("00:37", "That makes the whole reel unusable because the verses and concept text disappear."),
        ],
        "summary": "The export path drops commentary overlays even though the editor preview looks correct.",
        "items": [
            item("Bug Moment", "The exported MP4 loses the commentary card that was visible in preview.", "Bug moment", "After export, the MP4 shows the clip but the commentary card is gone.", "00:21", "00:31", 0.95),
            item("User Impact", "The reel becomes unusable because the concept text and verse references are missing from the final file.", "Impact", "The whole reel is unusable because the verses and concept text disappear.", "00:37", "00:46", 0.94),
            item("Visual Symptom", "The preview looks correct, which hides the fact that the export path is dropping the overlay.", "Symptom", "The commentary overlay is visible in the editor preview.", "00:08", "00:16", 0.9),
        ],
    },
    {
        "workflow": "supportQA",
        "instructions": "Identify the bug, the reproduction path, and why it matters to the user.",
        "voice": "Use the subtitle safe-area bug on vertical output.",
        "max": 3,
        "transcript": [
            line("00:07", "The subtitles look fine in the project window."),
            line("00:20", "On the exported vertical video, the bottom lines run off screen."),
            line("00:35", "That means the key quote is cut off in the final file."),
        ],
        "summary": "The vertical export lets subtitle lines escape the safe area even though the in-app preview looks fine.",
        "items": [
            item("Bug", "The bottom subtitle lines run off screen in the exported vertical file.", "Bug moment", "On the exported vertical video, the bottom lines run off screen.", "00:20", "00:28", 0.95),
            item("Reproduction Path", "Preview the project, export the vertical variant, and compare the bottom subtitle placement.", "Repro", "The subtitles look fine in the project window. On the exported vertical video, the bottom lines run off screen.", "00:07", "00:28", 0.91),
            item("Why It Matters", "The key quote is cut off in the final file, so the content becomes harder to understand and share.", "Impact", "That means the key quote is cut off in the final file.", "00:35", "00:43", 0.93),
        ],
    },
    {
        "workflow": "supportQA",
        "instructions": "Surface the bug moment, reproduction path, and user impact from this commentary-reel report.",
        "voice": "This is the missing-context issue where clips start too late.",
        "max": 3,
        "transcript": [
            line("00:06", "The reel jumps right into the sentence we wanted to critique."),
            line("00:19", "It cuts off the lead-in, so I cannot hear the beginning of the thought."),
            line("00:34", "That makes the commentary feel unfair and harder to follow."),
        ],
        "summary": "The commentary reel is trimming too aggressively and losing the setup that gives the focused quote its meaning.",
        "items": [
            item("Bug Moment", "The generated reel starts too late and drops the lead-in before the focal sentence.", "Bug moment", "The reel jumps right into the sentence we wanted to critique.", "00:06", "00:15", 0.94),
            item("Reproduction Path", "Build the commentary reel and compare the generated clip against the surrounding source context.", "Repro", "It cuts off the lead-in, so I cannot hear the beginning of the thought.", "00:19", "00:27", 0.89),
            item("User Impact", "The commentary feels unfair and harder to follow because the source thought loses context.", "Impact", "That makes the commentary feel unfair and harder to follow.", "00:34", "00:42", 0.93),
        ],
    },
    {
        "workflow": "supportQA",
        "instructions": "Find the bug moment, clearest symptom, and impact.",
        "voice": "This one is about concept ordering getting scrambled.",
        "max": 3,
        "transcript": [
            line("00:10", "I grouped the reel by concept."),
            line("00:22", "After export, the clips are back in raw timestamp order."),
            line("00:38", "That ruins the whole point of answering one concept at a time."),
        ],
        "summary": "The export path loses the curated concept order and falls back to raw chronology.",
        "items": [
            item("Bug Moment", "The exported reel drops the concept grouping and reorders everything by source time.", "Bug moment", "After export, the clips are back in raw timestamp order.", "00:22", "00:31", 0.94),
            item("Clearest Symptom", "A concept-grouped reel comes out as a straight chronological cut.", "Symptom", "I grouped the reel by concept. After export, the clips are back in raw timestamp order.", "00:10", "00:31", 0.9),
            item("Impact", "The user loses the ability to answer one error category at a time, which breaks the editorial structure.", "Impact", "That ruins the whole point of answering one concept at a time.", "00:38", "00:46", 0.92),
        ],
    },
    {
        "workflow": "supportQA",
        "instructions": "Extract the bug moment, user impact, and correction path.",
        "voice": "This is the transcript-vs-caption typo problem.",
        "max": 3,
        "transcript": [
            line("00:09", "The generated captions say prophetic when the transcript clearly says pathetic."),
            line("00:24", "If I trust the captions, the commentary quote is wrong."),
            line("00:39", "I need a way to force the transcript text into the rendered captions before export."),
        ],
        "summary": "Caption refinement drift is changing the meaning of quoted source lines and corrupting the final commentary reel.",
        "items": [
            item("Bug Moment", "The rendered captions use the wrong word even though the transcript source is clear.", "Bug moment", "The generated captions say prophetic when the transcript clearly says pathetic.", "00:09", "00:18", 0.95),
            item("User Impact", "The commentary quote becomes inaccurate if the caption text drifts away from the transcript.", "Impact", "If I trust the captions, the commentary quote is wrong.", "00:24", "00:31", 0.92),
            item("Correction Path", "The workflow needs a way to force transcript-backed caption text into the export path.", "Fix direction", "I need a way to force the transcript text into the rendered captions before export.", "00:39", "00:49", 0.9),
        ],
    },
    {
        "workflow": "supportQA",
        "instructions": "Surface the bug, the reproduction path, and the user-visible outcome.",
        "voice": "Use the source-timestamp omission inside each concept card.",
        "max": 3,
        "transcript": [
            line("00:08", "The concept card shows the title and the verses."),
            line("00:20", "But the original source timestamp is missing from the overlay."),
            line("00:35", "That means I cannot point viewers back to the exact place in the original video."),
        ],
        "summary": "The overlay is missing the source timestamp, which removes the audit trail the commentary workflow depends on.",
        "items": [
            item("Bug", "The overlay omits the source timestamp even though the card still shows the concept title and verses.", "Bug moment", "The original source timestamp is missing from the overlay.", "00:20", "00:28", 0.94),
            item("Reproduction Path", "Build a commentary reel and inspect the exported concept card overlay.", "Repro", "The concept card shows the title and the verses. But the original source timestamp is missing from the overlay.", "00:08", "00:28", 0.9),
            item("Outcome", "Viewers lose the path back to the exact source location, which weakens trust in the reel.", "Impact", "I cannot point viewers back to the exact place in the original video.", "00:35", "00:44", 0.92),
        ],
    },
    {
        "workflow": "podcastRepurpose",
        "instructions": "Group this into clip-ready themes with short reusable hooks.",
        "voice": "This should create strong creator-facing clip ideas, not generic summaries.",
        "max": 2,
        "transcript": [
            line("00:06", "The most common mistake founders make is confusing attention with demand."),
            line("00:24", "You can get praise on social media and still have no real buyers."),
            line("00:41", "The better test is whether someone will pay, not whether someone will clap."),
            line("00:58", "Once you learn that, your roadmap gets much cleaner."),
        ],
        "summary": "The conversation splits into a warning about vanity metrics and a practical lesson about using payment as the real demand signal.",
        "items": [
            item("Attention Is Not Demand", "Praise and attention can look strong while real demand is still weak.", "Hook: attention is not demand", "The most common mistake founders make is confusing attention with demand. You can get praise on social media and still have no real buyers.", "00:06", "00:33", 0.95),
            item("Who Will Pay, Not Who Will Clap", "A cleaner roadmap starts when you test for payment instead of applause.", "Hook: who will pay, not who will clap", "The better test is whether someone will pay, not whether someone will clap. Once you learn that, your roadmap gets much cleaner.", "00:41", "00:58", 0.95),
        ],
    },
    {
        "workflow": "podcastRepurpose",
        "instructions": "Group this into clip themes with concise hooks.",
        "voice": "This episode is about local-first AI and why trust changes the market.",
        "max": 2,
        "transcript": [
            line("00:09", "A privacy-first editor does not just sound nicer. It unlocks buyers who would never touch a cloud recorder."),
            line("00:28", "For legal, healthcare, and internal strategy teams, trust is the feature."),
            line("00:46", "Once you realize that, local-first stops being marketing copy and starts being product strategy."),
        ],
        "summary": "The episode naturally splits into a buyer-unlock theme and a deeper theme about trust becoming the actual feature.",
        "items": [
            item("Privacy Unlocks Buyers", "A privacy-first editor unlocks buyers who would reject a cloud recorder outright.", "Hook: privacy unlocks buyers", "A privacy-first editor does not just sound nicer. It unlocks buyers who would never touch a cloud recorder.", "00:09", "00:23", 0.94),
            item("Trust Is The Feature", "For sensitive teams, trust is not a side benefit; it is the feature they are buying.", "Hook: trust is the feature", "For legal, healthcare, and internal strategy teams, trust is the feature. Local-first stops being marketing copy and starts being product strategy.", "00:28", "00:46", 0.94),
        ],
    },
    {
        "workflow": "podcastRepurpose",
        "instructions": "Group this long-form moment into reusable clip themes.",
        "voice": "Keep the hooks short and creator-friendly.",
        "max": 2,
        "transcript": [
            line("00:08", "If you can turn a sixty-minute call into concept cards, you stop drowning in raw chronology."),
            line("00:26", "The best clips are usually grouped by idea, not by the order they happened."),
            line("00:43", "That is what makes commentary reels feel intentional instead of random."),
        ],
        "summary": "The clip ideas center on moving from raw chronology to grouped concepts so the final edit feels deliberate.",
        "items": [
            item("Escape Raw Chronology", "Concept cards let creators stop drowning in a raw chronological timeline.", "Hook: escape raw chronology", "If you can turn a sixty-minute call into concept cards, you stop drowning in raw chronology.", "00:08", "00:20", 0.93),
            item("Group By Idea, Not Order", "The strongest commentary clips are grouped by idea instead of the order they happened.", "Hook: group by idea", "The best clips are usually grouped by idea, not by the order they happened. That is what makes commentary reels feel intentional instead of random.", "00:26", "00:43", 0.94),
        ],
    },
    {
        "workflow": "podcastRepurpose",
        "instructions": "Turn this into clip-ready themes with short hook language.",
        "voice": "This is about audit trails in AI editing.",
        "max": 2,
        "transcript": [
            line("00:10", "AI editing gets dangerous when you cannot trace a claim back to the source."),
            line("00:28", "That is why timestamps and excerpts matter more than clever copy."),
            line("00:45", "An audit trail is what makes the AI feel usable instead of spooky."),
        ],
        "summary": "The repurpose path splits into one hook about traceability and another about why audit trails make AI editing feel trustworthy.",
        "items": [
            item("Trace Every Claim", "AI editing becomes dangerous when the edit cannot be traced back to the source.", "Hook: trace every claim", "AI editing gets dangerous when you cannot trace a claim back to the source.", "00:10", "00:21", 0.94),
            item("Audit Trail Beats Clever Copy", "Timestamps and excerpts matter more than flashy copy because they make the AI feel trustworthy.", "Hook: audit trail beats clever copy", "Timestamps and excerpts matter more than clever copy. An audit trail is what makes the AI feel usable instead of spooky.", "00:28", "00:45", 0.94),
        ],
    },
]


def render_transcript(lines: list[tuple[str, str]]) -> str:
    return "\n".join(f"[{ts}] {text}" for ts, text in lines)


def payload_for(scenario: dict) -> str:
    return json.dumps(
        {
            "workflow": scenario["workflow"],
            "summary": scenario["summary"],
            "items": scenario["items"],
        },
        ensure_ascii=True,
    )


def standard_prompt(scenario: dict) -> str:
    return (
        "Build a workflow plan for SaneVideo.\n"
        f"Workflow: {scenario['workflow']}\n"
        f"Instructions: {scenario['instructions']}\n"
        f"Max moments: {scenario['max']}\n"
        f"Transcript:\n{render_transcript(scenario['transcript'])}\n"
        "Return only valid JSON."
    )


def guarded_prompt(scenario: dict) -> str:
    return (
        "Create a transcript-grounded SaneVideo workflow draft.\n"
        f"Workflow pack: {scenario['workflow']}\n"
        f"Brief: {scenario['instructions']}\n"
        f"Limit: {scenario['max']} items\n"
        "Use only the supplied transcript. No markdown. No code fences. Do not use "
        '{"operations": [...]}.\n'
        f"Transcript excerpt:\n{render_transcript(scenario['transcript'])}\n"
        "Return only valid JSON with workflow, summary, and items."
    )


def voice_brief_prompt(scenario: dict) -> str:
    return (
        "Build a SaneVideo workflow plan from this transcript.\n"
        f"Workflow: {scenario['workflow']}\n"
        f"Voice brief summary: {scenario['voice']}\n"
        f"Editable target: {scenario['max']} moments maximum\n"
        "Keep every claim grounded in the transcript timestamps below.\n"
        f"Transcript:\n{render_transcript(scenario['transcript'])}\n"
        "Return only valid JSON."
    )


def repair_prompt(scenario: dict) -> str:
    return (
        "A previous model answered with the wrong schema:\n"
        '{"operations":[{"type":"commentary","summary":"bad draft","items":[{"concept":"wrong shape"}]}]}\n'
        "Rewrite it into the correct SaneVideo workflow JSON.\n"
        f"Workflow: {scenario['workflow']}\n"
        f"Focus: {scenario['instructions']}\n"
        f"Max moments: {scenario['max']}\n"
        f"Transcript:\n{render_transcript(scenario['transcript'])}\n"
        "Return only valid JSON. Do not include operations."
    )


PROMPT_BUILDERS = [standard_prompt, guarded_prompt, voice_brief_prompt, repair_prompt]


def message_example(prompt: str, answer: str) -> dict:
    return {
        "messages": [
            {"role": "system", "content": PLACEHOLDER},
            {"role": "user", "content": prompt},
            {"role": "assistant", "content": answer},
        ]
    }


def build_examples() -> list[dict]:
    examples: list[dict] = []
    for scenario in SCENARIOS:
        answer = payload_for(scenario)
        for builder in PROMPT_BUILDERS:
            examples.append(message_example(builder(scenario), answer))
    return examples


def split_examples(examples: list[dict]) -> tuple[list[dict], list[dict]]:
    train: list[dict] = []
    valid: list[dict] = []
    for index, example in enumerate(examples):
        if index % 5 == 0:
            valid.append(example)
        else:
            train.append(example)
    return train, valid


def write_jsonl(path: Path, examples: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for example in examples:
            handle.write(json.dumps(example, ensure_ascii=True) + "\n")


def main() -> None:
    examples = build_examples()
    train, valid = split_examples(examples)
    write_jsonl(TRAIN_PATH, train)
    write_jsonl(VALID_PATH, valid)
    print(f"Generated {len(train)} train and {len(valid)} valid examples.")


if __name__ == "__main__":
    main()
