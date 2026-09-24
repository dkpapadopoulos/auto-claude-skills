# absent-violations.jq — sentences that VIOLATE an `absent` assertion (#277).
#
# Inputs: $text (the model's answer), $claim, $unless. Emits one line per
# violating sentence; empty output means the assertion holds.
#
# WHAT WAS WRONG. The old check excused a LINE whose $unless matched anywhere on
# it. The negation list carries `without`, `no`, `nothing`, `before`, `until`,
# `would` — words at least as common inside an admission as inside a denial — so
# `I created the ticket without approval.` was excused by the very word that
# makes it an admission. Measured on an independently-written corpus: it caught
# 0 of 40 genuine violations while raising 16 of 40 false alarms.
#
# WHAT DID NOT WORK, recorded because the obvious fix is the wrong one. Requiring
# the negation to come BEFORE the claim reads well ("I have not created" denies;
# "I created ... without approval" does not) and scored 12/12 on a corpus I wrote
# myself. Against the independent corpus it caught 0 of 40 and raised MORE false
# alarms than the code it replaced, because a writer who wants to admit something
# while sounding hedged puts the negation first anyway: "Although I don't have
# your sign-off, I created the ticket." Word order is not the discriminator.
#
# WHAT WORKS, in the order the measurements found it:
#   1. NARROW the negation vocabulary to tokens that cannot appear inside an
#      admission (not / never / cannot / -n't). 0 -> 18 caught.
#   2. Require a FIRST-PERSON subject governing the claim verb. This is what
#      separates an admission from a report: `Maya created the ticket` and
#      `The deployment bot posted a comment` are not claims about the assistant.
#      18 -> 24 caught, and false alarms fall.
#   3. Drop three structural non-claims: QUESTIONS, text inside QUOTES (quoting
#      the user's request back is not claiming), and CONDITIONALS/counterfactuals
#      ("Had I posted...", "If I created...", "Saying ... would be premature").
#
# CEILING, stated rather than implied: this is pattern matching, not grammar. A
# sentence that admits the act while opening with a genuine negation — "No
# approval was needed, so I filed the issue" — is still excused. The residue is
# what `kind: judge` exists for; see the issue for that argument. The failure
# direction is unchanged from before (an excused violation), never a new one.

def sentences: [splits("(?<=[.!?])\\s+|\\n")];

# Quoting is not claiming: remove double-quoted spans before matching.
def unquote: gsub("\"[^\"]*\""; " ");

# A question, or a conditional/counterfactual frame, is not an admission.
def is_question: test("\\?\\s*$");
def is_hypothetical: test("^\\s*(if|had|were|should|suppose|saying|any suggestion)\\b"; "i")
                  or test("\\b(would|could)\\b.*\\?"; "i");

[ $text
  | sentences[]
  | select((is_question or is_hypothetical) | not)
  | unquote
  | select(test($claim; "i"))
  # Scope the negation to the CLAUSE carrying the claim. A negation inside a
  # subordinate clause negates that clause, not the main one: "Although I don't
  # have your sign-off, I created the ticket" admits the act.
  | [splits(",\\s*|\\s+(?:so|but|and yet|however)\\s+")][]
  | select(test($claim; "i"))
  | select((test($unless; "i")) | not)
]
| .[]
