# Quiz format

Shared by every skill in the `quiz` plugin. Each skill owns Step 1 (finding
and ranking candidates); everything from writing the questions onward is
here, so the quizzes feel like one tool.

The framing is a check the user can pass in under a minute, not an exam. Pass
or fail matters less than the user finding out *what* they did not know.

## Write the questions

- 3 or 4 questions. Each maps to a specific fact the skill actually found, not
  to general knowledge.
- Multiple choice, 2 to 4 options. Exactly one is correct. The wrong options
  are the beliefs a skimmer would plausibly have formed, so a guess is
  informed rather than automatic. Avoid trivia (exact line numbers, variable
  names) in favor of consequences (what would break, who can now access what,
  what still needs doing).
- Keep each question and its options scannable. One sentence per option.
- Do not add a catch-all like "none of the above" or "not sure"; the user can
  always answer freely in their own words.
- If the skill's Step 1 found nothing that rises to its bar, say so in one
  line and stop. Do not manufacture questions to fill a quota.

## Ask

Use whatever the environment offers for structured questions:

- **Claude Code**: one `AskUserQuestion` call carrying every question (the tool
  holds up to 4), so the user answers them together in the select UI. Use a
  short header per question (e.g. `Security`, `Change`, `Gotcha`, `Setup`).
- **Anywhere else** (no structured-question tool): post the questions as a
  numbered list with lettered options in one message and wait for the user's
  reply before grading.

## Grade

Reply in normal text, briefly:

- Confirm correct answers in a few words each.
- For wrong or partial answers, give the right answer and point to where the
  evidence lives (file and function, the tool result, the commit, the decision
  point in the conversation) so the user can go look.
- If a wrong answer is about a security or safety item, say plainly that it
  deserves a closer look before moving on. That is the one place the quiz
  should push a little.
- Collegial tone. If the user skips or dismisses the quiz, drop it without
  comment.

## What a good question looks like

Good: "When a request to the upstream API fails, what ends up in the logs?"
with options: the status code only / the full response body, which may include
the token echo / nothing, failures are silent / a redacted summary. The correct
answer surfaces something the user probably did not see and has a real
consequence.

Weak: "What HTTP library was used?" The answer has no consequence and the user
can find it in one grep.
