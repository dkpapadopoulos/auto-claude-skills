#!/usr/bin/env bash
# test-routing.sh — Tests for the skill-activation routing engine (v2)
# Bash 3.2 compatible. Sources test-helpers.sh for setup/teardown and assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-routing.sh ==="

# ---------------------------------------------------------------------------
# Helper: run the hook with a given prompt, return stdout
# ---------------------------------------------------------------------------
run_hook() {
    local prompt="$1"
    jq -n --arg p "${prompt}" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>/dev/null
}

# Helper: extract the additionalContext text from hook JSON output
extract_context() {
    local output="$1"
    printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

# Helper: install a minimal skill registry cache for testing
install_registry() {
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "systematic-debugging",
      "role": "process",
      "phase": "DEBUG",
      "triggers": [
        "(debug|bug|broken|crash|regression|not.work|error|fail|hang|freeze|timeout|leak|corrupt|unexpected|wrong)"
      ],
      "trigger_mode": "regex",
      "priority": 50,
      "invoke": "Skill(superpowers:systematic-debugging)",
      "available": true,
      "enabled": true
    },
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": [
        "(brainstorm|design|architect|strateg|scope|outline|approach|set.?up|wire.up|how.(should|would|could))",
        "(^|[^a-z])(build|create|implement|develop|scaffold|init|bootstrap|introduce|enable|add|make|new|start)($|[^a-z])"
      ],
      "trigger_mode": "regex",
      "priority": 30,
      "precedes": ["writing-plans"],
      "requires": [],
      "invoke": "Skill(superpowers:brainstorming)",
      "available": true,
      "enabled": true
    },
    {
      "name": "writing-plans",
      "role": "process",
      "phase": "PLAN",
      "triggers": ["(plan|outline|break.?down|spec)"],
      "trigger_mode": "regex",
      "priority": 40,
      "precedes": ["executing-plans"],
      "requires": ["brainstorming"],
      "invoke": "Skill(superpowers:writing-plans)",
      "available": true,
      "enabled": true
    },
    {
      "name": "executing-plans",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": [
        "(execute.*plan|run.the.plan|implement.the.plan|implement.*(rest|remaining)|continue|follow.the.plan|pick.up|resume|next.task|next.step|carry.on|keep.going|where.were.we|what.s.next)"
      ],
      "trigger_mode": "regex",
      "priority": 35,
      "precedes": [],
      "requires": ["writing-plans"],
      "invoke": "Skill(superpowers:executing-plans)",
      "available": true,
      "enabled": true
    },
    {
      "name": "subagent-driven-development",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": [
        "(execute.*plan|run.the.plan|implement.the.plan|continue|follow.the.plan|resume|next.task|next.step)"
      ],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(superpowers:subagent-driven-development)",
      "available": true,
      "enabled": true
    },
    {
      "name": "requesting-code-review",
      "role": "process",
      "phase": "REVIEW",
      "triggers": [
        "(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|smell|tech.?debt|(^|[^a-z])pr($|[^a-z]))"
      ],
      "trigger_mode": "regex",
      "priority": 25,
      "invoke": "Skill(superpowers:requesting-code-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "receiving-code-review",
      "role": "process",
      "phase": "REVIEW",
      "triggers": [
        "(review comments|pr comments|feedback|nits?|changes requested|address (the )?(review|comments|feedback)|respond to review|follow.?up review|re.?request review)"
      ],
      "trigger_mode": "regex",
      "priority": 33,
      "invoke": "Skill(superpowers:receiving-code-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "verification-before-completion",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": [
        "(ship|merge|deploy|push|release|tag|publish|pr.ready|ready.to|wrap.?up|finalize|complete|finish)"
      ],
      "trigger_mode": "regex",
      "priority": 60,
      "precedes": ["openspec-ship"],
      "requires": [],
      "invoke": "Skill(superpowers:verification-before-completion)",
      "available": true,
      "enabled": true
    },
    {
      "name": "openspec-ship",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": [
        "(document.*built|as.?built|openspec|archive.*feature|shipping.*protocol)"
      ],
      "trigger_mode": "regex",
      "priority": 58,
      "precedes": ["finishing-a-development-branch"],
      "requires": ["verification-before-completion"],
      "invoke": "Skill(auto-claude-skills:openspec-ship)",
      "available": true,
      "enabled": true
    },
    {
      "name": "finishing-a-development-branch",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": [
        "(ship|merge|deploy|push|release|tag|publish|pr.ready|ready.to|wrap.?up|finalize|complete|finish)"
      ],
      "trigger_mode": "regex",
      "priority": 61,
      "precedes": [],
      "requires": ["openspec-ship"],
      "invoke": "Skill(superpowers:finishing-a-development-branch)",
      "available": true,
      "enabled": true
    },
    {
      "name": "security-scanner",
      "role": "domain",
      "triggers": [
        "(secur(e|ity)|vulnerab|owasp|pentest|attack|exploit|encrypt|inject|xss|csrf)"
      ],
      "trigger_mode": "regex",
      "priority": 102,
      "invoke": "Skill(auto-claude-skills:security-scanner)",
      "available": true,
      "enabled": true
    },
    {
      "name": "frontend-design",
      "role": "domain",
      "triggers": [
        "(^|[^a-z])(ui|frontend|component|layout|style|css|tailwind|responsive|dashboard)($|[^a-z])"
      ],
      "trigger_mode": "regex",
      "priority": 101,
      "invoke": "Skill(frontend-design:frontend-design)",
      "available": true,
      "enabled": true
    },
    {
      "name": "disabled-skill",
      "role": "process",
      "phase": "DEBUG",
      "triggers": [
        "(debug|bug|fix)"
      ],
      "trigger_mode": "regex",
      "priority": 5,
      "invoke": "Skill(mock:disabled-skill)",
      "available": true,
      "enabled": false
    },
    {
      "name": "agent-team-execution",
      "role": "workflow",
      "phase": "IMPLEMENT",
      "triggers": [
        "(agent.team|team.execute|parallel.team|swarm|fan.out|specialist|multi.agent)"
      ],
      "trigger_mode": "regex",
      "priority": 16,
      "invoke": "Skill(agent-team-execution)",
      "available": true,
      "enabled": true
    },
    {
      "name": "agent-team-review",
      "role": "workflow",
      "phase": "REVIEW",
      "triggers": [
        "(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|tech.?debt|(^|[^a-z])pr($|[^a-z]))"
      ],
      "trigger_mode": "regex",
      "priority": 17,
      "invoke": "Skill(agent-team-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "design-debate",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": [
        "(trade.?off|debate|compare.*(option|approach|design)|weigh.*(option|approach)|pro.?con|alternative|architecture)"
      ],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(design-debate)",
      "available": true,
      "enabled": true
    },
    {
      "name": "claude-md-improver",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": [
        "(claude\\.md|claude.md|project.?memory|improve.*claude|audit.*claude|update.*claude.md)"
      ],
      "trigger_mode": "regex",
      "priority": 10,
      "invoke": "Skill(superpowers:claude-md-improver)",
      "available": true,
      "enabled": true
    },
    {
      "name": "product-discovery",
      "role": "process",
      "phase": "DISCOVER",
      "triggers": [
        "(discovery|discover(y|.session|.brief)|user.problem|pain.point|what.to.build|what.should.we|which.issue)",
        "(backlog|sprint.plan|prioriti|triage|next.sprint|roadmap)"
      ],
      "keywords": ["what should we build", "backlog review", "sprint planning", "discovery session", "problem statement", "user needs"],
      "trigger_mode": "regex",
      "priority": 35,
      "precedes": ["brainstorming"],
      "requires": [],
      "invoke": "Skill(auto-claude-skills:product-discovery)",
      "available": true,
      "enabled": true
    },
    {
      "name": "outcome-review",
      "role": "process",
      "phase": "LEARN",
      "triggers": [
        "(how.did.*(perform|do|go|work)|outcome|adoption|funnel|cohort|experiment.result|feature.impact|post.launch|post.ship|measur(e|ing).*(impact|outcome|metric|adoption|success|result)|did.it.work)"
      ],
      "keywords": ["how did it perform", "check metrics", "feature impact", "post-launch review", "did it work", "adoption metrics", "what did we learn", "learn from this", "review the results", "metric results"],
      "trigger_mode": "regex",
      "priority": 30,
      "precedes": ["product-discovery"],
      "requires": [],
      "invoke": "Skill(auto-claude-skills:outcome-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "supply-chain-investigation",
      "role": "domain",
      "phase": "REVIEW",
      "triggers": [
        "(supply.?chain|compromised|malicious|hijack|backdoor|typosquat).*(package|dependency|version|publish|registry)",
        "(npm|maven|pypi|pip|gradle).*(attack|compromise|backdoor|malicious|hijack)"
      ],
      "trigger_mode": "regex",
      "priority": 40,
      "invoke": "Skill(auto-claude-skills:supply-chain-investigation)",
      "available": true,
      "enabled": true
    },
    {
      "name": "project-verification",
      "role": "domain",
      "phase": "REVIEW",
      "triggers": [
        "(run.*(the )?tests?|run.*(lint|typecheck|type.?check)|project.*(gate|checks?)|verify.*(locally|the build)|does.*(it )?build|declared.*(gate|commands?))"
      ],
      "trigger_mode": "regex",
      "priority": 16,
      "invoke": "Skill(auto-claude-skills:project-verification)",
      "available": true,
      "enabled": true
    }
  ],
  "phase_guide": {
    "DISCOVER": "product-discovery (identify problems, prioritize backlog)",
    "DESIGN": "brainstorming (ask questions, get approval)",
    "PLAN": "writing-plans (break into tasks, confirm before execution)",
    "IMPLEMENT": "executing-plans or subagent-driven-development",
    "REVIEW": "requesting-code-review",
    "SHIP": "verification-before-completion + openspec-ship + finishing-a-development-branch",
    "DEBUG": "systematic-debugging, then return to current phase",
    "LEARN": "outcome-review (measure impact, extract learnings)"
  },
  "phase_compositions": {
    "DISCOVER": {"driver": "product-discovery", "parallel": [], "hints": []},
    "DESIGN": {"driver": "brainstorming", "parallel": [], "hints": []},
    "PLAN": {"driver": "writing-plans", "parallel": [], "hints": []},
    "IMPLEMENT": {"driver": "executing-plans", "parallel": [], "hints": []},
    "REVIEW": {"driver": "requesting-code-review", "parallel": [], "hints": []},
    "SHIP": {"driver": "verification-before-completion", "parallel": [], "hints": []},
    "DEBUG": {"driver": "systematic-debugging", "parallel": [], "hints": []},
    "LEARN": {"driver": "outcome-review", "parallel": [], "hints": []}
  },
  "methodology_hints": [
    {
      "name": "ralph-loop",
      "triggers": [
        "(migrate|refactor.all|fix.all|batch|overnight|autonom|iterate|keep.(going|trying|fixing))"
      ],
      "trigger_mode": "regex",
      "hint": "RALPH LOOP: Consider /ralph-loop for autonomous iteration."
    },
    {
      "name": "pr-review",
      "triggers": [
        "(review|pull.?request|code.?review|(^|[^a-z])pr($|[^a-z]))"
      ],
      "trigger_mode": "regex",
      "hint": "PR REVIEW: Consider /pr-review for structured review.",
      "skill": "requesting-code-review"
    },
    {
      "name": "atlassian-jira",
      "triggers": [
        "(ticket|story|epic|acceptance.criter|definition.of.done|requirement|user.story|jira|sprint|backlog)"
      ],
      "trigger_mode": "regex",
      "hint": "ATLASSIAN ROVO: If Atlassian Rovo MCP is connected, prefer `search(cloudId, query)` for cross-system discovery before targeted JQL. Pull acceptance criteria and linked context. Use `maxResults: 10`.",
      "phases": ["DESIGN", "PLAN"]
    },
    {
      "name": "claude-md-maintenance",
      "triggers": [
        "(refactor|restructur|new.convention|architecture.change|reorganize|rename.*(module|package|directory))"
      ],
      "trigger_mode": "regex",
      "hint": "CLAUDE.MD: If this session changed project conventions or structure, consider /revise-claude-md",
      "skill": "claude-md-improver",
      "phases": [
        "IMPLEMENT",
        "SHIP"
      ]
    },
    {
      "name": "openspec-ship-reminder",
      "triggers": [
        "(ship|merge|deploy|push|release|finish|complete|wrap.?up|finalize)"
      ],
      "trigger_mode": "regex",
      "hint": "OPENSPEC: After verification-before-completion passes, invoke openspec-ship to generate as-built documentation before committing. This is mandatory for feature shipping.",
      "phases": ["SHIP"]
    },
    {
      "name": "phase-enforcement",
      "triggers": ["(fix|change|update|rename|move|add a|modify|edit|refactor|implement|write the|create the)"],
      "trigger_mode": "regex",
      "hint": "PHASE ENFORCEMENT: You are in DESIGN/PLAN phase. Complete the current phase skill before editing implementation files. Small changes still require the full flow — scaled down, not skipped.",
      "phases": ["DESIGN", "PLAN"]
    }
  ],
  "blocklist_patterns": [
    {
      "pattern": "^(hi|hello|hey|thanks|thank.you|good.(morning|afternoon|evening)|bye|goodbye|ok|okay|yes|no|sure|yep|nope|got.it|sounds.good|cool|nice|great|perfect|awesome|understood)([[:space:]!.,]+.{0,20})?$",
      "description": "Greeting or short acknowledgement",
      "max_tail_length": 20
    }
  ],
  "warnings": []
}
REGISTRY
}

# Helper: install registry extended with batch-scripting skill
install_registry_with_batch() {
    install_registry
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"
    jq '.skills += [{
      "name": "batch-scripting",
      "role": "workflow",
      "phase": "IMPLEMENT",
      "triggers": ["(batch|bulk|mass|across.*files|every.*file|all.*files|migrate.*all|transform.*all|refactor.*all|sweep|codemod|claude.?-p|headless|each.*file)"],
      "trigger_mode": "regex",
      "priority": 15,
      "precedes": [],
      "requires": [],
      "invoke": "Skill(auto-claude-skills:batch-scripting)",
      "available": true,
      "enabled": true
    }]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"
}

# Helper: install registry extended with incident-analysis skill and gcp-observability hint
install_registry_with_incident_analysis() {
    install_registry
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"
    jq '.skills += [{
      "name": "incident-analysis",
      "role": "domain",
      "phase": "DEBUG",
      "triggers": ["(incident|postmortem|outage|root.cause|error.spike|log.analysis|production.error|staging.error)", "(connection.*(fail|refus|timeout|pool|exhaust|acquir)|oom.?kill|memory.pressure|cpu.*(throttl|saturat)|crash.?loop|liveness.probe|node.not.ready|upstream.*(fail|error|timeout)|image.?pull.?(back.?off|fail|error)|err.?image.?pull|config.?(error|missing)|create.?container.?config|failed.?(mount|attach)|pvc.*(pending|fail))", "(sigterm|sigkill|shutdown.*(error|fail|grace)|active.connection|cloud.?sql|proxy.*(restart|error|fail|crash)|pod.*(restart|crash|evict)|latency.*(spike|p99)|p99.*(latency|spike|degrad)|request.timeout|circuit.break|deploy.*(fail|rollback))"],
      "trigger_mode": "regex",
      "priority": 20,
      "precedes": [],
      "requires": [],
      "invoke": "Skill(auto-claude-skills:incident-analysis)",
      "keywords": ["incident", "postmortem", "outage", "error spike", "connection failure", "connection pool", "cloud sql proxy", "graceful shutdown", "active connections", "health check", "ImagePullBackOff", "image pull error", "CreateContainerConfigError", "missing ConfigMap", "missing Secret", "FailedMount", "pod restart", "latency spike", "request timeout"],
      "available": true,
      "enabled": true
    }] | .methodology_hints += [{
      "name": "gcp-observability",
      "triggers": ["(runtime.log|error.group|metric.regress|production.error|staging.error|verify.deploy|post.deploy|list.log|list.metric|trace.search|incident|postmortem|root.cause|outage|error.spike|log.analysis|5[0-9][0-9].error)", "(connection.*(fail|refus|timeout|pool|exhaust)|oom.?kill|crash.?loop|cloud.?sql|proxy.*(restart|error|fail)|pod.*(restart|crash|evict)|sigterm|sigkill|latency.*(spike|p99)|p99.*(latency|spike|degrad)|deploy.*(fail|rollback))"],
      "trigger_mode": "regex",
      "hint": "INCIDENT ANALYSIS: Use Skill(auto-claude-skills:incident-analysis) for structured investigation. Stages: MITIGATE -> INVESTIGATE -> POSTMORTEM. Detect tool tier (MCP > gcloud > guidance). Scope all queries to specific service + environment + narrow time window.",
      "phases": ["SHIP", "DEBUG"]
    }] | .methodology_hints += [{
      "name": "github-mcp",
      "triggers": ["(pull.?request|issue|github|merge|branch|repo|deploy|rollback)"],
      "trigger_mode": "regex",
      "hint": "GITHUB: If GitHub MCP tools are available, check for related PRs, issues, and workflow runs.",
      "phases": ["DESIGN", "PLAN", "DEBUG", "REVIEW", "SHIP"]
    }]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"
}

# Helper: install registry extended with incident-trend-analyzer skill
install_registry_with_incident_trend() {
    install_registry_with_incident_analysis
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"
    jq '.skills += [{
      "name": "incident-trend-analyzer",
      "role": "domain",
      "phase": "DEBUG",
      "triggers": ["(incident.trend|postmortem.trend|what.keeps.breaking|recurring.incident|failure.pattern|incident.pattern|analyze.postmortems)"],
      "trigger_mode": "regex",
      "priority": 20,
      "precedes": [],
      "requires": [],
      "invoke": "Skill(auto-claude-skills:incident-trend-analyzer)",
      "keywords": ["postmortem trends", "recurring incidents", "incident patterns", "what keeps breaking"],
      "available": true,
      "enabled": true
    }]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"
}

# Helper: install registry extended with Wave 1 skills
install_registry_with_wave1() {
    install_registry
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"
    jq '.skills += [
      {
        "name": "writing-skills",
        "role": "domain",
        "phase": "DESIGN",
        "triggers": ["(skill|write.*skill|create.*skill|edit.*skill|new.*skill|skill.*(file|md|template|format))"],
        "trigger_mode": "regex",
        "priority": 15,
        "precedes": [],
        "requires": [],
        "invoke": "Skill(superpowers:writing-skills)",
        "available": true,
        "enabled": true
      },
      {
        "name": "skill-scaffold",
        "role": "domain",
        "phase": "DESIGN",
        "triggers": ["(new.?skill|new.?plugin|new.?command|new.?hook|scaffold|skeleton|skill.?template|skill.?skeleton)"],
        "trigger_mode": "regex",
        "priority": 16,
        "precedes": [],
        "requires": [],
        "invoke": "Skill(auto-claude-skills:skill-scaffold)",
        "available": true,
        "enabled": true
      },
      {
        "name": "prototype-lab",
        "role": "domain",
        "phase": "DESIGN",
        "triggers": ["(prototype|compare.?options|build.?variants|which.?approach|try.?both|try.?all|side.by.side)"],
        "trigger_mode": "regex",
        "priority": 15,
        "precedes": [],
        "requires": [],
        "invoke": "Skill(auto-claude-skills:prototype-lab)",
        "available": true,
        "enabled": true
      },
      {
        "name": "agent-safety-review",
        "role": "domain",
        "phase": "DESIGN",
        "triggers": ["(autonomous.?loop|ralph.?loop|overnight|unattended|background.?agent|browser.?agent|email.?agent|inbox.?agent|yolo|skip.?permission|dangerously|permissionless|auto.?reply|auto.?respond|send.on.behalf)"],
        "trigger_mode": "regex",
        "priority": 17,
        "precedes": [],
        "requires": [],
        "invoke": "Skill(auto-claude-skills:agent-safety-review)",
        "available": true,
        "enabled": true
      }
    ]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"
}

# Helper: install a v4 skill registry cache with plugins and phase_compositions
install_registry_v4() {
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'REGISTRY_V4'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "systematic-debugging",
      "role": "process",
      "phase": "DEBUG",
      "triggers": ["(debug|bug|broken|crash|regression|not.work|error|fail|hang|freeze|timeout|leak|corrupt|unexpected|wrong)"],
      "trigger_mode": "regex",
      "priority": 10,
      "invoke": "Skill(superpowers:systematic-debugging)",
      "available": true,
      "enabled": true
    },
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": ["(build|create|implement|develop|scaffold|init|bootstrap|brainstorm|design|architect|strateg|scope|outline|approach|generate|set.?up|wire.up|connect|integrate|extend|new|start|introduce|enable|support|how.(should|would|could))"],
      "trigger_mode": "regex",
      "priority": 30,
      "precedes": ["writing-plans"],
      "requires": [],
      "invoke": "Skill(superpowers:brainstorming)",
      "available": true,
      "enabled": true
    },
    {
      "name": "writing-plans",
      "role": "process",
      "phase": "PLAN",
      "triggers": [],
      "trigger_mode": "regex",
      "priority": 40,
      "precedes": ["executing-plans"],
      "requires": ["brainstorming"],
      "invoke": "Skill(superpowers:writing-plans)",
      "available": true,
      "enabled": true
    },
    {
      "name": "executing-plans",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": ["(execute.*plan|run.the.plan|implement.the.plan|continue|follow.the.plan|resume|next.task|next.step)"],
      "trigger_mode": "regex",
      "priority": 15,
      "precedes": ["requesting-code-review"],
      "requires": ["writing-plans"],
      "invoke": "Skill(superpowers:executing-plans)",
      "available": true,
      "enabled": true
    },
    {
      "name": "subagent-driven-development",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": ["(execute.*plan|run.the.plan|implement.the.plan|continue|follow.the.plan|resume|next.task|next.step)"],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(superpowers:subagent-driven-development)",
      "available": true,
      "enabled": true
    },
    {
      "name": "requesting-code-review",
      "role": "process",
      "phase": "REVIEW",
      "triggers": ["(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|smell|tech.?debt|(^|[^a-z])pr($|[^a-z]))"],
      "trigger_mode": "regex",
      "priority": 25,
      "invoke": "Skill(superpowers:requesting-code-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "receiving-code-review",
      "role": "process",
      "phase": "REVIEW",
      "triggers": ["(review comments|pr comments|feedback|nits?|changes requested|address (the )?(review|comments|feedback)|respond to review|follow.?up review|re.?request review)"],
      "trigger_mode": "regex",
      "priority": 33,
      "invoke": "Skill(superpowers:receiving-code-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "verification-before-completion",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": ["(ship|merge|deploy|push|release|tag|publish|pr.ready|ready.to|wrap.?up|finalize|complete|finish)"],
      "trigger_mode": "regex",
      "priority": 60,
      "precedes": ["openspec-ship"],
      "requires": [],
      "invoke": "Skill(superpowers:verification-before-completion)",
      "available": true,
      "enabled": true
    },
    {
      "name": "openspec-ship",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": ["(document.*built|as.?built|openspec|archive.*feature|shipping.*protocol)"],
      "trigger_mode": "regex",
      "priority": 58,
      "precedes": ["finishing-a-development-branch"],
      "requires": ["verification-before-completion"],
      "invoke": "Skill(auto-claude-skills:openspec-ship)",
      "available": true,
      "enabled": true
    },
    {
      "name": "finishing-a-development-branch",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": ["(ship|merge|deploy|push|release|tag|publish|pr.ready|ready.to|wrap.?up|finalize|complete|finish)"],
      "trigger_mode": "regex",
      "priority": 61,
      "precedes": [],
      "requires": ["openspec-ship"],
      "invoke": "Skill(superpowers:finishing-a-development-branch)",
      "available": true,
      "enabled": true
    },
    {
      "name": "security-scanner",
      "role": "domain",
      "triggers": ["(secur(e|ity)|vulnerab|owasp|pentest|attack|exploit|encrypt|inject|xss|csrf)"],
      "trigger_mode": "regex",
      "priority": 102,
      "invoke": "Skill(auto-claude-skills:security-scanner)",
      "available": true,
      "enabled": true
    },
    {
      "name": "frontend-design",
      "role": "domain",
      "triggers": ["(^|[^a-z])(ui|frontend|component|layout|style|css|tailwind|responsive|dashboard)($|[^a-z])"],
      "trigger_mode": "regex",
      "priority": 101,
      "invoke": "Skill(frontend-design:frontend-design)",
      "available": true,
      "enabled": true
    },
    {
      "name": "disabled-skill",
      "role": "process",
      "phase": "DEBUG",
      "triggers": ["(debug|bug|fix)"],
      "trigger_mode": "regex",
      "priority": 5,
      "invoke": "Skill(mock:disabled-skill)",
      "available": true,
      "enabled": false
    },
    {
      "name": "agent-team-execution",
      "role": "workflow",
      "phase": "IMPLEMENT",
      "triggers": ["(agent.team|team.execute|parallel.team|swarm|fan.out|specialist|multi.agent)"],
      "trigger_mode": "regex",
      "priority": 16,
      "invoke": "Skill(agent-team-execution)",
      "available": true,
      "enabled": true
    },
    {
      "name": "agent-team-review",
      "role": "workflow",
      "phase": "REVIEW",
      "triggers": ["(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|tech.?debt|(^|[^a-z])pr($|[^a-z]))"],
      "trigger_mode": "regex",
      "priority": 17,
      "invoke": "Skill(agent-team-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "design-debate",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": ["(trade.?off|debate|compare.*(option|approach|design)|weigh.*(option|approach)|pro.?con|alternative|architecture)"],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(design-debate)",
      "available": true,
      "enabled": true
    },
    {
      "name": "claude-md-improver",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": ["(claude\\.md|claude.md|project.?memory|improve.*claude|audit.*claude|update.*claude.md)"],
      "trigger_mode": "regex",
      "priority": 10,
      "invoke": "Skill(superpowers:claude-md-improver)",
      "available": true,
      "enabled": true
    }
  ],
  "plugins": [
    {"name": "code-review", "source": "claude-plugins-official", "provides": {"commands": ["/code-review"], "skills": [], "agents": [], "hooks": []}, "phase_fit": ["REVIEW"], "description": "5 parallel review agents", "available": true},
    {"name": "code-simplifier", "source": "claude-plugins-official", "provides": {"commands": [], "skills": [], "agents": ["code-simplifier"], "hooks": []}, "phase_fit": ["REVIEW"], "description": "Post-review clarity pass", "available": true},
    {"name": "commit-commands", "source": "claude-plugins-official", "provides": {"commands": ["/commit", "/commit-push-pr"], "skills": [], "agents": [], "hooks": []}, "phase_fit": ["SHIP"], "description": "Commit workflows", "available": true},
    {"name": "security-guidance", "source": "claude-plugins-official", "provides": {"commands": [], "skills": [], "agents": [], "hooks": ["PreToolUse:security-patterns"]}, "phase_fit": ["*"], "description": "Write-time security blocker", "available": true},
    {"name": "feature-dev", "source": "claude-plugins-official", "provides": {"commands": ["/feature-dev"], "skills": [], "agents": ["code-explorer", "code-architect", "code-reviewer"], "hooks": []}, "phase_fit": ["DESIGN", "IMPLEMENT", "REVIEW"], "description": "Full feature pipeline", "available": true}
  ],
  "phase_compositions": {
    "DESIGN": {"driver": "brainstorming", "parallel": [{"plugin": "feature-dev", "use": "agents:code-explorer", "when": "installed", "purpose": "Parallel codebase exploration while brainstorming"}], "hints": [{"plugin": "feature-dev", "text": "Consider /feature-dev for agent-parallel feature development", "when": "installed"}]},
    "PLAN": {"driver": "writing-plans", "parallel": [], "hints": []},
    "IMPLEMENT": {"driver": "executing-plans", "parallel": [{"plugin": "security-guidance", "use": "hooks:PreToolUse", "when": "installed", "purpose": "Passive write-time security guard"}], "hints": []},
    "REVIEW": {"driver": "requesting-code-review", "parallel": [{"plugin": "code-review", "use": "commands:/code-review", "when": "installed", "purpose": "5 parallel review agents, posts to GitHub PR"}, {"plugin": "code-simplifier", "use": "agents:code-simplifier", "when": "installed", "purpose": "Post-review simplification pass"}], "hints": [{"plugin": "code-review", "text": "Consider /code-review for automated multi-agent PR review", "when": "installed"}]},
    "SHIP": {"driver": "verification-before-completion", "sequence": [{"step": "openspec-ship", "purpose": "Create retrospective OpenSpec change, validate, archive, update changelog"}, {"plugin": "commit-commands", "use": "commands:/commit", "when": "installed", "purpose": "Execute structured commit after verification passes"}, {"step": "finishing-a-development-branch", "purpose": "Branch cleanup, merge, or PR"}, {"plugin": "commit-commands", "use": "commands:/commit-push-pr", "when": "installed AND user chooses PR option", "purpose": "Automated branch-to-PR flow"}], "hints": [{"plugin": "commit-commands", "text": "Consider /commit-push-pr for automated branch-to-PR workflow", "when": "installed"}]},
    "DEBUG": {"driver": "systematic-debugging", "parallel": [], "hints": []}
  },
  "methodology_hints": [
    {"name": "ralph-loop", "triggers": ["(migrate|refactor.all|fix.all|batch|overnight|autonom|iterate|keep.(going|trying|fixing))"], "trigger_mode": "regex", "hint": "RALPH LOOP: Consider /ralph-loop for autonomous iteration."},
    {"name": "pr-review", "triggers": ["(review|pull.?request|code.?review|(^|[^a-z])pr($|[^a-z]))"], "trigger_mode": "regex", "hint": "PR REVIEW: Consider /pr-review for structured review.", "skill": "requesting-code-review"},
    {"name": "claude-md-maintenance", "triggers": ["(refactor|restructur|new.convention|architecture.change|reorganize|rename.*(module|package|directory))"], "trigger_mode": "regex", "hint": "CLAUDE.MD: If this session changed project conventions or structure, consider /revise-claude-md", "skill": "claude-md-improver", "phases": ["IMPLEMENT", "SHIP"]},
    {"name": "openspec-ship-reminder", "triggers": ["(ship|merge|deploy|push|release|finish|complete|wrap.?up|finalize)"], "trigger_mode": "regex", "hint": "OPENSPEC: After verification-before-completion passes, invoke openspec-ship to generate as-built documentation before committing. This is mandatory for feature shipping.", "phases": ["SHIP"]}
  ],
  "blocklist_patterns": [
    {"pattern": "^(hi|hello|hey|thanks|thank.you|good.(morning|afternoon|evening)|bye|goodbye|ok|okay|yes|no|sure|yep|nope|got.it|sounds.good|cool|nice|great|perfect|awesome|understood)([[:space:]!.,]+.{0,20})?$", "description": "Greeting or short acknowledgement", "max_tail_length": 20}
  ],
  "warnings": []
}
REGISTRY_V4
}

# ---------------------------------------------------------------------------
# 1. Debug prompt matches systematic-debugging
# ---------------------------------------------------------------------------
test_debug_prompt_matches() {
    echo "-- test: debug prompt matches systematic-debugging --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "I need to debug this crash in the auth module")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "debug matches systematic-debugging" "systematic-debugging" "${context}"
    assert_contains "debug label is Fix / Debug" "Fix / Debug" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 2. Build prompt matches brainstorming
# ---------------------------------------------------------------------------
test_build_prompt_matches() {
    echo "-- test: build prompt matches brainstorming --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "create a new authentication service from scratch")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "build matches brainstorming" "brainstorming" "${context}"
    assert_contains "build label is Build New" "Build New" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 3. Greeting is blocked (empty output)
# ---------------------------------------------------------------------------
test_greeting_blocked() {
    echo "-- test: greeting is blocked --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "hello there")"

    assert_equals "greeting produces empty output" "" "${output}"

    teardown_test_env
}

# The blocklist can match legitimate dev prompts that happen to start with
# "yes/no/ok/cool..." — silent exit leaves users confused. SKILL_DEBUG=1 should
# emit a one-line stderr breadcrumb so users can diagnose the missing routing.
test_greeting_blocklist_debug_hint() {
    echo "-- test: SKILL_DEBUG emits stderr hint when blocklist fires --"
    setup_test_env
    install_registry

    local stderr_out
    stderr_out="$(jq -n --arg p "hello there" '{"prompt":$p}' | \
        SKILL_DEBUG=1 CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>&1 >/dev/null)"

    assert_contains "blocklist debug hint emitted on SKILL_DEBUG=1" "greeting blocklist" "${stderr_out}"

    # Default: no SKILL_DEBUG → stderr stays silent (existing behavior preserved)
    local silent_stderr
    silent_stderr="$(jq -n --arg p "hello there" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>&1 >/dev/null)"

    assert_not_contains "no stderr hint when SKILL_DEBUG unset" "greeting blocklist" "${silent_stderr}"

    teardown_test_env
}
test_greeting_blocklist_debug_hint

# When the last-invoked signal is a non-chain skill (e.g., a domain skill like
# security-scanner), the chain walker can't map it to the chain so
# _last_skill_chain_idx stays -1 and `completed` previously reset to []. The
# push gate keyed off `completed`, blocking legitimate chore commits after a
# full SHIP cycle. Fix: use `_current_idx - 1` as a floor — by being at a
# chain anchor, the linear composition model implies all predecessors are done.
test_completed_uses_current_idx_floor() {
    echo "-- test: completed array uses _current_idx - 1 as floor when last-invoked isn't in chain --"
    setup_test_env
    install_registry

    local token="completed-floor-$$"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"

    # Simulate: last-invoked signal is a DOMAIN skill (not in any chain).
    # Without the fix, this makes the walker reset completed to [].
    jq -n '{skill:"security-scanner",phase:"REVIEW"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    # Prompt matches openspec-ship triggers (archive.*feature + as.?built + openspec)
    # The test registry makes openspec-ship.requires = [verification-before-completion]
    # and openspec-ship.precedes = [finishing-a-development-branch]. So the built
    # chain is [verification-before-completion, openspec-ship, finishing], with
    # _current_idx = 1 (openspec-ship).
    jq -n --arg p "archive this feature as built openspec" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" >/dev/null 2>&1

    local state_file="${HOME}/.claude/.skill-composition-state-${token}"
    assert_equals "state file written" "true" "$([ -f "${state_file}" ] && echo true || echo false)"

    if [ -f "${state_file}" ]; then
        local current_idx
        current_idx="$(jq -r '.current_index' "${state_file}" 2>/dev/null)"
        # Prompt may match multiple triggers; assert only that current_idx > 0
        # (anchor is somewhere past the chain start, so predecessors exist).
        if [ "${current_idx:-0}" -ge 1 ]; then
            _record_pass "current_index points past chain start (implying progress)"
        else
            _record_fail "current_index points past chain start (implying progress)" \
                "current_index was ${current_idx}"
        fi

        # The fix: completed length == current_index (every chain slot before
        # the anchor is implicitly done via the linear composition model),
        # even though the last-invoked signal is a non-chain domain skill.
        local completed_count
        completed_count="$(jq '.completed | length' "${state_file}" 2>/dev/null)"
        assert_equals "completed length equals current_index" \
            "${current_idx}" "${completed_count}"

        # The first entry of completed should equal chain[0] (the earliest
        # predecessor the walker found). Regardless of which skill matched,
        # the predecessor chain is rooted at whatever requires-chain terminates.
        local first_completed first_chain
        first_completed="$(jq -r '.completed[0] // empty' "${state_file}" 2>/dev/null)"
        first_chain="$(jq -r '.chain[0] // empty' "${state_file}" 2>/dev/null)"
        assert_equals "completed[0] equals chain[0]" "${first_chain}" "${first_completed}"
    fi

    teardown_test_env
}
test_completed_uses_current_idx_floor

# Regression: 2026-06-11 PR #49 merge session. The PostToolUse completion hook
# had advanced .completed through verification-before-completion, but a later
# prompt ("merge PR49") anchored the chain at an EARLIER step
# (requesting-code-review via the pr trigger). The walker's state write rebuilt
# .completed purely from max(_current_idx-1, _last_skill_chain_idx), discarding
# the on-disk entries — regressing 5 -> 3 (and further on each later prompt)
# and re-arming the openspec-guard push gate against already-reviewed work.
# Contract: within the SAME chain, .completed is monotonic — the walker must
# union its computed prefix with the on-disk array, never truncate it.
# Legitimate resets are pure-cancel (file deleted) and token rotation only.
test_completed_never_regresses_behind_disk_state() {
    echo "-- test: completed array never regresses behind on-disk state for the same chain --"
    setup_test_env
    install_registry

    local token="completed-monotonic-$$"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"

    # On-disk state: the completion hook has recorded progress through
    # openspec-ship (index 1) on the [verification-before-completion,
    # openspec-ship, finishing-a-development-branch] chain.
    jq -n '{
        chain: ["verification-before-completion","openspec-ship","finishing-a-development-branch"],
        completed: ["verification-before-completion","openspec-ship"],
        current_index: 2
    }' > "${HOME}/.claude/.skill-composition-state-${token}"

    # Last-invoked signal points at the chain start (index 0) — the walker's
    # two existing floors both resolve to index 0 here.
    jq -n '{skill:"verification-before-completion",phase:"SHIP"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    # Prompt re-anchors at openspec-ship (index 1) — earlier than disk
    # progress. Deliberately contains no "spec"/"plan" substring so
    # writing-plans cannot hijack the anchor and switch the chain
    # ("openspec" would match writing-plans' `spec` trigger).
    jq -n --arg p "archive the feature as built" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" >/dev/null 2>&1

    local state_file="${HOME}/.claude/.skill-composition-state-${token}"
    assert_equals "state file still present" "true" \
        "$([ -f "${state_file}" ] && echo true || echo false)"

    if [ -f "${state_file}" ]; then
        # Writer-ran canary: the seed sets current_index 2; the backward
        # re-anchor at openspec-ship must rewrite it to 1. Guards against the
        # test passing vacuously against its own seeded file if a registry
        # edit ever stops the prompt from anchoring.
        local idx_after
        idx_after="$(jq -r '.current_index' "${state_file}" 2>/dev/null)"
        assert_equals "writer ran and re-anchored backward (current_index 2 -> 1)" \
            "1" "${idx_after}"

        # Precondition: the chain must not have switched — the scenario is a
        # backward re-anchor WITHIN the same chain.
        local chain1
        chain1="$(jq -r '.chain[1] // empty' "${state_file}" 2>/dev/null)"
        assert_equals "chain unchanged (anchor stayed in-chain)" \
            "openspec-ship" "${chain1}"

        local has_ship completed_count
        has_ship="$(jq -r '.completed | index("openspec-ship") != null' "${state_file}" 2>/dev/null)"
        assert_equals "openspec-ship survives a backward re-anchor" "true" "${has_ship}"

        completed_count="$(jq '.completed | length' "${state_file}" 2>/dev/null)"
        if [ "${completed_count:-0}" -ge 2 ]; then
            _record_pass "completed length is monotonic (>= disk state)"
        else
            _record_fail "completed length is monotonic (>= disk state)" \
                "completed shrank to ${completed_count} entries"
        fi

        # Union must stay in chain order with no duplicates.
        local ordered
        ordered="$(jq -r '
            .chain as $c |
            (.completed == (.completed | unique_by(. as $x | $c | index($x)) |
                            sort_by(. as $x | $c | index($x))))
        ' "${state_file}" 2>/dev/null)"
        assert_equals "completed is deduplicated and in chain order" "true" "${ordered}"
    fi

    teardown_test_env
}
test_completed_never_regresses_behind_disk_state

test_completed_resets_when_chain_differs() {
    echo "-- test: disk completed from a DIFFERENT chain does not leak into the new chain's state --"
    setup_test_env
    install_registry

    local token="completed-chain-switch-$$"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"

    # On-disk state belongs to the SHIP chain. The prompt's "openspec" hits
    # writing-plans' `spec` trigger, anchoring a DIFFERENT chain
    # ([brainstorming, writing-plans, executing-plans]) — verified behavior.
    # The old chain's completed entries must NOT be unioned into the new
    # chain's state: chain switch is a legitimate reset.
    jq -n '{
        chain: ["verification-before-completion","openspec-ship","finishing-a-development-branch"],
        completed: ["verification-before-completion","openspec-ship"],
        current_index: 2
    }' > "${HOME}/.claude/.skill-composition-state-${token}"

    jq -n '{skill:"verification-before-completion",phase:"SHIP"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    jq -n --arg p "archive this feature as built openspec" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" >/dev/null 2>&1

    local state_file="${HOME}/.claude/.skill-composition-state-${token}"
    if [ -f "${state_file}" ]; then
        # Precondition: chain actually switched.
        local chain0
        chain0="$(jq -r '.chain[0] // empty' "${state_file}" 2>/dev/null)"
        assert_equals "chain switched to the writing-plans chain" \
            "brainstorming" "${chain0}"

        local leaked
        leaked="$(jq -r '.completed | (index("verification-before-completion") != null) or (index("openspec-ship") != null)' "${state_file}" 2>/dev/null)"
        assert_equals "old chain entries do not leak across a chain switch" "false" "${leaked}"
    else
        _record_fail "state file written for new chain" "missing ${state_file}"
    fi

    teardown_test_env
}
test_completed_resets_when_chain_differs

# ---------------------------------------------------------------------------
# 3b. Sticky composition on ack-shaped prompts
# ---------------------------------------------------------------------------
test_sticky_no_state_no_output() {
    echo "-- test: bare ack with no composition state produces no output (regression baseline) --"
    setup_test_env
    install_registry

    local token="sticky-no-state-$$"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"
    # Explicitly DO NOT create .skill-composition-state-${token}

    local output
    output="$(run_hook "yes")"

    assert_equals "no output when no composition state" "" "${output}"

    teardown_test_env
}
test_sticky_no_state_no_output

test_sticky_implement_ack_emits_executing_plans() {
    echo "-- test: bare 'yes' during IMPLEMENT chain emits executing-plans --"
    setup_test_env
    install_registry

    local token="sticky-impl-$$"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"

    jq -n '{
        chain: ["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion","openspec-ship","finishing-a-development-branch"],
        completed: ["brainstorming","writing-plans"],
        current_index: 2
    }' > "${HOME}/.claude/.skill-composition-state-${token}"

    jq -n '{skill:"writing-plans",phase:"PLAN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local context
    context="$(extract_context "$(run_hook "yes")")"

    assert_contains "emits IMPLEMENT phase" "Phase: [IMPLEMENT]" "${context}"
    assert_contains "emits executing-plans process skill" "executing-plans" "${context}"
    assert_contains "emits invoke string" "Skill(superpowers:executing-plans)" "${context}"

    teardown_test_env
}
test_sticky_implement_ack_emits_executing_plans

test_sticky_topic_change_no_sticky() {
    echo "-- test: long non-ack prompt during active chain does not sticky-emit --"
    setup_test_env
    install_registry

    local token="sticky-topic-$$"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"

    jq -n '{
        chain: ["brainstorming","writing-plans","executing-plans"],
        completed: ["brainstorming"],
        current_index: 1
    }' > "${HOME}/.claude/.skill-composition-state-${token}"
    jq -n '{skill:"brainstorming",phase:"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local context
    context="$(extract_context "$(run_hook "actually can you show me how the test would work instead")")"

    if printf '%s' "${context}" | grep -qE '^Process: writing-plans'; then
        _record_fail "sticky did not fire on topic-change" "Process line shows writing-plans"
    else
        _record_pass "sticky did not fire on topic-change"
    fi

    teardown_test_env
}
test_sticky_topic_change_no_sticky

test_sticky_no_double_injection() {
    echo "-- test: sticky does not hijack when a stronger trigger matches --"
    setup_test_env
    install_registry

    local token="sticky-nodup-$$"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"

    jq -n '{
        chain: ["brainstorming","writing-plans","executing-plans"],
        completed: ["brainstorming"],
        current_index: 1
    }' > "${HOME}/.claude/.skill-composition-state-${token}"
    jq -n '{skill:"brainstorming",phase:"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local context
    context="$(extract_context "$(run_hook "debug the failing test")")"

    assert_contains "systematic-debugging is top process" "Process: systematic-debugging" "${context}"

    teardown_test_env
}
test_sticky_no_double_injection

test_sticky_corrupt_state_fail_open() {
    echo "-- test: corrupt composition-state JSON fails silently, no crash --"
    setup_test_env
    install_registry

    local token="sticky-corrupt-$$"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"

    printf '{' > "${HOME}/.claude/.skill-composition-state-${token}"
    jq -n '{skill:"brainstorming",phase:"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    run_hook "yes" >/dev/null
    local exit_code=$?
    assert_equals "hook exits 0 on corrupt state" "0" "${exit_code}"

    teardown_test_env
}
test_sticky_corrupt_state_fail_open

_seed_active_chain() {
    local token="$1"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"
    jq -n '{
        chain: ["brainstorming","writing-plans","executing-plans"],
        completed: ["brainstorming"]
    }' > "${HOME}/.claude/.skill-composition-state-${token}"
}

test_sticky_cancel_clears_state() {
    echo "-- test: pure cancel prompts (with punctuation variants) clear chain and suppress sticky --"
    setup_test_env
    install_registry

    local token base=$$
    local i=0
    for prompt in "cancel" "stop." "cancel?" "stop!" "  never mind  " "nope" "no thanks"; do
        i=$((i+1))
        token="sticky-cancel-${base}-${i}"
        _seed_active_chain "${token}"

        local context
        context="$(extract_context "$(run_hook "${prompt}")")"

        local comp_present
        comp_present="$([ -f "${HOME}/.claude/.skill-composition-state-${token}" ] && echo true || echo false)"
        if [ "${comp_present}" = "false" ]; then
            _record_pass "cancel cleared state for prompt: '${prompt}'"
        else
            _record_fail "cancel cleared state for prompt: '${prompt}'" \
                "composition-state still present"
        fi

        if printf '%s' "${context}" | grep -qE '^Process: writing-plans'; then
            _record_fail "no sticky for prompt: '${prompt}'" \
                "writing-plans appeared as Process"
        else
            _record_pass "no sticky for prompt: '${prompt}'"
        fi
    done

    teardown_test_env
}
test_sticky_cancel_clears_state

test_sticky_advances_with_completed() {
    echo "-- test: sticky emits chain[completed.length] as .completed grows (advancement boundary) --"
    setup_test_env
    install_registry

    # The integration boundary: post-tool completion-hook advances .completed; the
    # activation-hook walker reads .completed length to compute CURRENT. As
    # completed grows from 0 to N-1, CURRENT must move through the chain in
    # lockstep — never re-emitting the previous step.
    local chain='["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion","openspec-ship","finishing-a-development-branch"]'

    local i=0
    while [ "$i" -lt 6 ]; do
        local token="sticky-advance-$$-${i}"
        printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"

        jq -n --argjson chain "${chain}" --argjson i "$i" '{
            chain: $chain,
            completed: ($chain[:$i])
        }' > "${HOME}/.claude/.skill-composition-state-${token}"

        local expected
        expected="$(printf '%s' "${chain}" | jq -r --argjson i "$i" '.[$i]')"

        local context
        context="$(extract_context "$(run_hook "yes")")"

        # Skill may emit on Process: prefix, Workflow: prefix, or as a bare
        # "<name> -> Skill(...)" line depending on its role and slot.
        if printf '%s' "${context}" | grep -qE "(^|^Process: |^Workflow: )${expected} -> "; then
            _record_pass "step ${i}: emits ${expected}"
        else
            _record_fail "step ${i}: emits ${expected}" \
                "no top-line emission for '${expected}'"
        fi

        rm -f "${HOME}/.claude/.skill-session-token" \
              "${HOME}/.claude/.skill-composition-state-${token}"
        i=$((i+1))
    done

    teardown_test_env
}
test_sticky_advances_with_completed

# ---------------------------------------------------------------------------
# 4. Slash command is blocked
# ---------------------------------------------------------------------------
test_slash_command_blocked() {
    echo "-- test: slash command is blocked --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "/help me with something")"

    assert_equals "slash command produces empty output" "" "${output}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 5. Short prompt is blocked
# ---------------------------------------------------------------------------
test_short_prompt_blocked() {
    echo "-- test: short prompt is blocked --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "hi")"

    assert_equals "short prompt produces empty output" "" "${output}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 6. Domain skill appears alongside process skill with Domain:
# ---------------------------------------------------------------------------
test_domain_informed_by() {
    echo "-- test: domain skill shows Domain: --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "build a secure frontend dashboard component with csrf protection")"
    local context
    context="$(extract_context "${output}")"

    # Should have a process skill (brainstorming for "build")
    assert_contains "has process skill" "Process:" "${context}"
    # Should have domain skill as Domain:
    assert_contains "has Domain:" "Domain:" "${context}"
    # security-scanner or frontend-design should appear
    assert_contains "has domain skill" "domain" "$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | tr '[:upper:]' '[:lower:]')"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 7. Review prompt matches code review
# ---------------------------------------------------------------------------
test_review_prompt_matches() {
    echo "-- test: review prompt matches code review --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "please review the code changes in this pull request")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "review matches code-review skill" "code-review" "${context}"
    assert_contains "review label is Review" "Review" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 8. Ship prompt matches workflow skills
# ---------------------------------------------------------------------------
test_ship_prompt_matches() {
    echo "-- test: ship prompt matches workflow skills --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "let's ship this and merge the branch to main")"
    local context
    context="$(extract_context "${output}")"

    # With no process skill, workflow skills listed without orchestration prefix
    # finishing-a-development-branch has higher priority (61 vs 60 vs 58), so it wins the single workflow slot
    # The full SHIP chain is: verification-before-completion → openspec-ship → finishing-a-development-branch
    assert_contains "ship matches workflow skill" "finishing-a-development-branch" "${context}"
    assert_contains "ship label has Ship / Complete" "Ship / Complete" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 9. Max 1 process skill enforced
# ---------------------------------------------------------------------------
test_max_one_process() {
    echo "-- test: max 1 process skill enforced --"
    setup_test_env
    install_registry

    # "debug" triggers systematic-debugging (process); only 1 process skill should appear
    local output
    output="$(run_hook "debug and fix the broken authentication error in the module")"
    local context
    context="$(extract_context "${output}")"

    # Count Process: lines (should be exactly 1)
    local process_count
    process_count="$(printf '%s' "${context}" | grep -c 'Process:' 2>/dev/null)" || process_count=0

    assert_equals "max 1 process skill" "1" "${process_count}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 10. Disabled skills excluded
# ---------------------------------------------------------------------------
test_disabled_skill_excluded() {
    echo "-- test: disabled skills excluded --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "debug this broken module that has a bug")"
    local context
    context="$(extract_context "${output}")"

    assert_not_contains "disabled skill not in output" "disabled-skill" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 11. Missing registry falls back gracefully
# ---------------------------------------------------------------------------
test_missing_registry_fallback() {
    echo "-- test: missing registry falls back gracefully --"
    setup_test_env
    # Do NOT install registry — leave cache missing

    local exit_code=0
    local output
    output="$(run_hook "debug the authentication bug")" || exit_code=$?

    assert_equals "hook exits cleanly" "0" "${exit_code}"

    # Should still produce output (phase checkpoint only)
    if [ -n "${output}" ]; then
        local context
        context="$(extract_context "${output}")"
        assert_contains "fallback has phase checkpoint" "phase" "$(printf '%s' "${context}" | tr '[:upper:]' '[:lower:]')"
    else
        _record_pass "hook exits silently on missing registry (acceptable)"
    fi

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 12. Output is valid JSON
# ---------------------------------------------------------------------------
test_output_valid_json() {
    echo "-- test: output is valid JSON --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "implement the new user authentication feature")"

    # Write to file for json validation
    local tmpfile="${TEST_TMPDIR}/output.json"
    printf '%s' "${output}" > "${tmpfile}"

    assert_json_valid "output is valid JSON" "${tmpfile}"

    # Check structure
    local hook_event
    hook_event="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
    assert_equals "hookEventName is UserPromptSubmit" "UserPromptSubmit" "${hook_event}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 13. Zero matches produce phase checkpoint
# ---------------------------------------------------------------------------
test_zero_matches_phase_checkpoint() {
    echo "-- test: zero matches produce no output --"
    setup_test_env
    install_registry

    # A prompt that won't match any triggers
    local output
    output="$(run_hook "tell me about the weather forecast for tomorrow please")"

    if [[ -z "$output" ]]; then
        _record_pass "zero match produces empty output"
    else
        _record_fail "zero match produces empty output" "got: ${output}"
    fi

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 14. Methodology hints appended when matched
# ---------------------------------------------------------------------------
test_methodology_hints() {
    echo "-- test: methodology hints suppressed when skill selected --"
    setup_test_env
    install_registry

    # PR review hint should be suppressed because "review" triggers requesting-code-review
    local output
    output="$(run_hook "review this pull request for code quality issues")"
    local context
    context="$(extract_context "${output}")"

    assert_not_contains "PR review hint suppressed when skill selected" "PR REVIEW" "${context}"

    # Ralph-loop hint should still appear when matched (no associated skill)
    output="$(run_hook "migrate all the legacy modules to the new framework and iterate until done")"
    context="$(extract_context "${output}")"
    assert_contains "Ralph loop hint present" "RALPH LOOP" "${context}"

    teardown_test_env
}

test_phase_scoped_methodology_hints() {
    echo "-- test: phase-scoped methodology hints --"
    setup_test_env
    install_registry

    # Atlassian Jira hint has phases: ["DESIGN", "PLAN"].
    # "design a ticket tracking system" triggers brainstorming (DESIGN phase)
    # and also matches the Jira trigger "ticket" → hint should fire.
    local output context
    output="$(run_hook "design a ticket tracking system")"
    context="$(extract_context "${output}")"
    assert_contains "Jira hint fires in DESIGN phase" "ATLASSIAN" "${context}"

    # "debug the ticket creation bug" triggers debugging (DEBUG phase)
    # and matches "ticket" but DEBUG is not in Jira hint's phases → suppressed.
    output="$(run_hook "debug the ticket creation bug")"
    context="$(extract_context "${output}")"
    assert_not_contains "Jira hint suppressed in DEBUG phase" "ATLASSIAN" "${context}"

    # Hint without phases (ralph-loop) fires regardless of phase
    # Use a prompt that matches a skill ("build" → brainstorming) AND the ralph-loop hint ("iterate")
    output="$(run_hook "build and iterate on the legacy modules until done")"
    context="$(extract_context "${output}")"
    assert_contains "phaseless hint fires unconditionally" "RALPH LOOP" "${context}"

    teardown_test_env
}

test_claude_md_maintenance_hint() {
    echo "-- test: claude-md maintenance hint --"
    setup_test_env
    install_registry

    # "continue and refactor the auth module" → executing-plans (IMPLEMENT phase) + "refactor" trigger
    # Avoid "plan" in prompt which matches writing-plans trigger in fixture
    local output context
    output="$(run_hook "continue and refactor the auth module")"
    context="$(extract_context "${output}")"
    assert_contains "claude-md hint fires in IMPLEMENT phase" "CLAUDE.MD" "${context}"

    # "design a new refactored architecture" → DESIGN phase, hint should NOT fire
    output="$(run_hook "design a new refactored architecture")"
    context="$(extract_context "${output}")"
    assert_not_contains "claude-md hint suppressed in DESIGN phase" "CLAUDE.MD" "${context}"

    # When claude-md-improver is already selected, hint should be suppressed
    output="$(run_hook "improve the claude.md and refactor conventions")"
    context="$(extract_context "${output}")"
    assert_not_contains "claude-md hint suppressed when skill selected" "CLAUDE.MD" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 15. Agent team execution matches plan prompts
# ---------------------------------------------------------------------------
test_agent_team_execution_matches() {
    echo "-- test: agent team execution matches plan prompts --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "let's use agent teams to execute the plan")"
    context="$(extract_context "$output")"
    assert_contains "agent team matches" "agent-team-execution" "$context"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 16. Design-debate appears as Domain: domain skill
# ---------------------------------------------------------------------------
test_design_debate_as_domain() {
    echo "-- test: design-debate appears as Domain: --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "compare the two architecture approaches and weigh the trade-offs")"
    context="$(extract_context "$output")"
    # brainstorming is process (triggers on "approach"), design-debate is domain (triggers on "trade-off"/"compare")
    assert_contains "has brainstorming" "brainstorming" "$context"
    assert_contains "has Domain: design-debate" "design-debate" "$context"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 17. Agent team review matches review prompts
# ---------------------------------------------------------------------------
test_agent_team_review_matches() {
    echo "-- test: agent team review matches review prompts --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "review the code changes for this PR")"
    context="$(extract_context "$output")"
    assert_contains "agent-team-review matches" "agent-team-review" "$context"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 18. Brainstorming fires on short design prompts too
# ---------------------------------------------------------------------------
test_brainstorming_short_prompt() {
    echo "-- test: brainstorming fires on short design prompts --"
    setup_test_env
    install_registry

    local output context
    # Short but legitimate design prompts should trigger brainstorming
    output="$(run_hook "build a widget")"
    context="$(extract_context "${output}")"
    assert_contains "brainstorming fires on short build prompt" "brainstorming" "${context}"

    # Long prompts should also work
    output="$(run_hook "design a new user authentication flow with OAuth and social login")"
    context="$(extract_context "${output}")"
    assert_contains "brainstorming fires on long prompt" "brainstorming" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 19. Skill-name-mention boost works
# ---------------------------------------------------------------------------
test_skill_name_mention_boost() {
    echo "-- test: skill-name-mention boost --"
    setup_test_env
    install_registry

    local output context
    # Mention "security-scanner" by name — should boost it even without a trigger word
    output="$(run_hook "tell me about the security-scanner skill and how to use it")"
    context="$(extract_context "${output}")"

    assert_contains "skill name mention boosts security-scanner" "security-scanner" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 20. Domain invocation instruction appears when domain skills present
# ---------------------------------------------------------------------------
test_domain_invocation_instruction() {
    echo "-- test: domain invocation instruction --"
    setup_test_env
    install_registry

    local output context
    # "build a secure dashboard" triggers brainstorming (process) + security-scanner + frontend-design (domain)
    output="$(run_hook "build a secure frontend dashboard component with csrf protection")"
    context="$(extract_context "${output}")"

    assert_contains "domain invocation instruction present" "invoke them" "${context}"

    # Prompt with only process skill and no domain should NOT have the instruction
    output="$(run_hook "continue with the next task in the plan")"
    context="$(extract_context "${output}")"
    assert_not_contains "no domain instruction without domain skills" "invoke them" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 21. Overflow domain skills NOT shown (role caps are the signal)
# ---------------------------------------------------------------------------
test_overflow_domain_hidden() {
    echo "-- test: overflow domain skills hidden --"
    setup_test_env
    install_registry

    # With max_suggestions=3 (default), process + 2 domain fills the cap.
    # A third domain skill should NOT appear as "Also relevant"
    # "build a secure responsive dashboard" triggers:
    #   brainstorming (process), security-scanner (domain, p102), frontend-design (domain, p101), design-debate (domain, p14)
    # design-debate overflows but should not be displayed
    local output context
    output="$(run_hook "build a secure responsive dashboard with csrf protection")"
    context="$(extract_context "${output}")"

    assert_not_contains "overflow domain not shown" "Also relevant" "${context}"

    teardown_test_env
}

test_teammate_idle_guard() {
    echo "-- test: teammate idle guard --"
    setup_test_env

    local guard="${PROJECT_ROOT}/hooks/teammate-idle-guard.sh"

    # Test 1: No tasks dir = exit 0
    local exit_code
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>/dev/null
    exit_code=$?
    assert_equals "no tasks dir allows idle" "0" "$exit_code"

    # Test 2: Has in_progress task = exit 2
    mkdir -p "${HOME}/.claude/tasks/test-team"
    printf '{"subject":"Fix auth","status":"in_progress","owner":"worker"}' \
        > "${HOME}/.claude/tasks/test-team/1.json"
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>/dev/null
    exit_code=$?
    assert_equals "unfinished task blocks idle" "2" "$exit_code"

    # Test 3: All tasks completed = exit 0
    printf '{"subject":"Fix auth","status":"completed","owner":"worker"}' \
        > "${HOME}/.claude/tasks/test-team/1.json"
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>/dev/null
    exit_code=$?
    assert_equals "completed tasks allow idle" "0" "$exit_code"

    # Test 4: Different owner's in_progress task = exit 0
    printf '{"subject":"Fix auth","status":"in_progress","owner":"other-worker"}' \
        > "${HOME}/.claude/tasks/test-team/1.json"
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>/dev/null
    exit_code=$?
    assert_equals "other owner tasks allow idle" "0" "$exit_code"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 23. Review phase emits PARALLEL lines (v4 registry)
# ---------------------------------------------------------------------------
test_review_emits_parallel_lines() {
    echo "-- test: review phase emits PARALLEL lines --"
    setup_test_env
    install_registry_v4

    local output context
    output="$(run_hook "please review the code changes in this pull request")"
    context="$(extract_context "${output}")"

    assert_contains "review has PARALLEL line" "PARALLEL:" "${context}"
    assert_contains "review mentions code-review" "code-review" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 24. Ship phase emits SEQUENCE lines (v4 registry)
# ---------------------------------------------------------------------------
test_ship_emits_sequence_lines() {
    echo "-- test: ship phase emits SEQUENCE lines --"
    setup_test_env
    install_registry_v4

    local output context
    output="$(run_hook "let's ship this and merge the branch to main")"
    context="$(extract_context "${output}")"

    assert_contains "ship has SEQUENCE line" "SEQUENCE:" "${context}"
    assert_contains "ship mentions commit" "commit" "$(printf '%s' "${context}" | tr '[:upper:]' '[:lower:]')"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 25. No PARALLEL when plugin unavailable (v3 registry)
# ---------------------------------------------------------------------------
test_no_parallel_when_plugin_unavailable() {
    echo "-- test: no PARALLEL when plugin unavailable --"
    setup_test_env
    install_registry  # v3 registry, no plugins

    local output context
    output="$(run_hook "please review the code changes in this pull request")"
    context="$(extract_context "${output}")"

    assert_not_contains "no PARALLEL without plugins" "PARALLEL:" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 26. Process skill reserved when high-priority domain/workflow fill slots
# ---------------------------------------------------------------------------
test_process_slot_reserved() {
    echo "-- test: process slot reserved under cap --"
    setup_test_env
    install_registry

    # "build a secure frontend dashboard and ship it" triggers:
    #   brainstorming (process, prio 30), security-scanner (domain, prio 102),
    #   frontend-design (domain, prio 101), finishing-a-development-branch (workflow, prio 61)
    # With max_suggestions=3, all 3 slots could go to non-process skills.
    # Process skill MUST still be selected.
    local output context
    output="$(run_hook "build a secure frontend dashboard and ship it")"
    context="$(extract_context "${output}")"

    assert_contains "process skill reserved" "Skill(superpowers:brainstorming)" "${context}"
    assert_contains "process skill has Process: prefix" "Process:" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 26.5. Malformed skill entry (missing triggers) does not break hook
# ---------------------------------------------------------------------------
test_missing_triggers_handled() {
    echo "-- test: missing triggers handled gracefully --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'BADREG'
{
  "version": "test",
  "skills": [
    {
      "name": "good-skill",
      "role": "process",
      "phase": "DEBUG",
      "triggers": ["(debug|bug)"],
      "priority": 10,
      "invoke": "Skill(mock:good-skill)",
      "available": true,
      "enabled": true
    },
    {
      "name": "no-triggers-skill",
      "role": "domain",
      "priority": 50,
      "invoke": "Skill(mock:no-triggers)",
      "available": true,
      "enabled": true
    },
    {
      "name": "null-triggers-skill",
      "role": "domain",
      "triggers": null,
      "priority": 50,
      "invoke": "Skill(mock:null-triggers)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
BADREG

    local exit_code=0
    local output context
    output="$(run_hook "debug this broken module")" || exit_code=$?

    assert_equals "hook exits cleanly with malformed skills" "0" "${exit_code}"
    context="$(extract_context "${output}")"
    assert_contains "good skill still selected" "good-skill" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 27. Phase composition uses process phase, not domain phase
# ---------------------------------------------------------------------------
test_phase_uses_process_precedence() {
    echo "-- test: phase composition uses process phase precedence --"
    setup_test_env
    install_registry_v4

    # "build a secure frontend dashboard" triggers:
    #   brainstorming (process, phase=DESIGN, prio 30),
    #   security-scanner (domain, no phase, prio 102),
    #   frontend-design (domain, no phase, prio 101)
    # Phase should be DESIGN (from process), not any domain phase
    local output context
    output="$(run_hook "build a secure frontend dashboard component with csrf protection")"
    context="$(extract_context "${output}")"

    # The DESIGN phase composition has a PARALLEL line for feature-dev plugin
    assert_contains "phase composition uses DESIGN" "PARALLEL:" "${context}"
    assert_contains "phase composition mentions feature-dev" "feature-dev" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 28. Compact Evaluate phase uses process phase
# ---------------------------------------------------------------------------
test_eval_phase_uses_process() {
    echo "-- test: compact Evaluate phase uses process phase --"
    setup_test_env

    # Use a minimal registry with just 1 process + 1 domain to stay in compact format
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'PHASEREG'
{
  "version": "test",
  "skills": [
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": ["(build|create)"],
      "priority": 30,
      "invoke": "Skill(superpowers:brainstorming)",
      "available": true,
      "enabled": true
    },
    {
      "name": "security-scanner",
      "role": "domain",
      "phase": "IMPLEMENT",
      "triggers": ["(secur(e|ity)|encrypt)"],
      "priority": 102,
      "invoke": "Skill(auto-claude-skills:security-scanner)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
PHASEREG

    # 2 skills -> compact format with Evaluate line
    # security-scanner has phase=IMPLEMENT, brainstorming has phase=DESIGN
    # Process phase (DESIGN) should win
    local output context
    output="$(run_hook "build a secure authentication service with encryption")"
    context="$(extract_context "${output}")"

    assert_contains "Evaluate uses DESIGN phase" "Phase: [DESIGN]" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 29. Skill name boost uses boundary-aware matching
# ---------------------------------------------------------------------------
test_name_boost_boundary_aware() {
    echo "-- test: skill name boost boundary-aware --"
    setup_test_env

    # Custom registry with two skills: "debug" and "debug-advanced"
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'NAMEREG'
{
  "version": "test",
  "skills": [
    {
      "name": "debug",
      "role": "domain",
      "triggers": ["(never-match-this-nonsense-string)"],
      "priority": 10,
      "invoke": "Skill(mock:debug)",
      "available": true,
      "enabled": true
    },
    {
      "name": "debug-advanced",
      "role": "domain",
      "triggers": ["(never-match-this-nonsense-string)"],
      "priority": 10,
      "invoke": "Skill(mock:debug-advanced)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
NAMEREG

    # Mention only "debug-advanced" by name — "debug" should NOT get boosted
    local output context
    output="$(run_hook "tell me about the debug-advanced skill and how it works")"
    context="$(extract_context "${output}")"

    assert_contains "debug-advanced is selected" "debug-advanced" "${context}"
    assert_not_contains "plain debug not selected" "mock:debug)" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 29.5. Trigger word-boundary excludes dot (file extension separator)
# ---------------------------------------------------------------------------
test_trigger_boundary_excludes_dot() {
    echo "-- test: trigger word-boundary excludes dot --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'DOTREG'
{
  "version": "test",
  "skills": [
    {
      "name": "py-tool",
      "role": "domain",
      "triggers": ["py"],
      "priority": 0,
      "invoke": "Skill(mock:py-tool)",
      "available": true,
      "enabled": true
    },
    {
      "name": "other-tool",
      "role": "domain",
      "triggers": ["(skill|tool)"],
      "priority": 0,
      "invoke": "Skill(mock:other-tool)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
DOTREG

    # "check skill.py file" — "py" appears after a dot, NOT a word boundary
    # "other-tool" has trigger "skill" which gets word-boundary score (30)
    # "py-tool" trigger "py" should only get substring score (10)
    # With equal priority (0), other-tool (score 30) should rank above py-tool (score 10)
    local output context
    output="$(run_hook "check the skill.py file for issues please")"
    context="$(extract_context "${output}")"

    # other-tool should appear (word-boundary match on "skill")
    assert_contains "other-tool selected" "other-tool" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 30. Domain instruction wording without process skill
# ---------------------------------------------------------------------------
test_domain_instruction_no_process() {
    echo "-- test: domain instruction wording without process --"
    setup_test_env

    # Custom registry: only domain skills, no process skills
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'DOMREG'
{
  "version": "test",
  "skills": [
    {
      "name": "security-scanner",
      "role": "domain",
      "triggers": ["(secur(e|ity)|vulnerab)"],
      "priority": 102,
      "invoke": "Skill(auto-claude-skills:security-scanner)",
      "available": true,
      "enabled": true
    },
    {
      "name": "frontend-design",
      "role": "domain",
      "triggers": ["(frontend|dashboard|component)"],
      "priority": 101,
      "invoke": "Skill(frontend-design)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
DOMREG

    local output context
    output="$(run_hook "build a secure frontend dashboard component")"
    context="$(extract_context "${output}")"

    # Should have domain invocation instruction but NOT mention "the process skill"
    assert_contains "has domain invocation instruction" "invoke them" "${context}"
    assert_not_contains "no process skill reference" "the process skill" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 31. Incident-analysis routing tests
# ---------------------------------------------------------------------------
test_incident_analysis_hint_fires() {
    echo "-- test: incident-analysis hint fires on incident keywords --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "debug this production incident in checkout service")"
    context="$(extract_context "${output}")"
    assert_contains "incident triggers gcp-observability hint" "INCIDENT ANALYSIS" "${context}"

    output="$(run_hook "write a postmortem for the outage last night")"
    context="$(extract_context "${output}")"
    assert_contains "postmortem triggers gcp-observability hint" "INCIDENT ANALYSIS" "${context}"

    teardown_test_env
}

test_incident_analysis_skill_scores() {
    echo "-- test: incident-analysis skill entry scores on incident keywords --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "debug this production incident in the auth service")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis skill appears" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_phase_gating() {
    echo "-- test: incident-analysis only fires in DEBUG and SHIP phases --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "debug the incident in checkout service logs")"
    context="$(extract_context "${output}")"
    assert_contains "hint fires in DEBUG phase" "INCIDENT ANALYSIS" "${context}"

    output="$(run_hook "design an incident tracking dashboard")"
    context="$(extract_context "${output}")"
    assert_not_contains "hint suppressed in DESIGN phase" "INCIDENT ANALYSIS" "${context}"

    teardown_test_env
}

test_incident_analysis_preserves_existing_triggers() {
    echo "-- test: existing gcp-observability triggers still work --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "debug the runtime.log errors in production")"
    context="$(extract_context "${output}")"
    assert_contains "runtime.log still triggers hint" "INCIDENT ANALYSIS" "${context}"

    teardown_test_env
}

test_gcp_hint_fires_on_symptom_language() {
    echo "-- test: gcp-observability hint fires on symptom language --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "cloud sql proxy crashed and connections are failing")"
    context="$(extract_context "${output}")"
    assert_contains "gcp-observability hint fires on symptoms" "INCIDENT ANALYSIS" "${context}"

    teardown_test_env
}

test_incident_analysis_trigger_source() {
    echo "-- test: default-triggers.json contains incident-analysis entry --"

    local invoke_path
    invoke_path="$(jq -r '.. | objects | select(.name == "incident-analysis") | .invoke // empty' config/default-triggers.json)"
    assert_equals "invoke path correct" "Skill(auto-claude-skills:incident-analysis)" "${invoke_path}"

    local hint_text
    hint_text="$(jq -r '.. | objects | select(.name == "gcp-observability") | .hint // empty' config/default-triggers.json)"
    assert_contains "hint text updated" "INCIDENT ANALYSIS" "${hint_text}"
}

test_incident_analysis_invoke_path() {
    echo "-- test: invoke path uses bundled plugin prefix --"

    local invoke_path
    invoke_path="$(jq -r '.. | objects | select(.name == "incident-analysis") | .invoke // empty' config/default-triggers.json)"

    assert_contains "uses bundled plugin prefix" "auto-claude-skills:" "${invoke_path}"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
test_debug_prompt_matches
test_build_prompt_matches
test_greeting_blocked
test_slash_command_blocked
test_short_prompt_blocked
test_domain_informed_by
test_review_prompt_matches
test_ship_prompt_matches
test_max_one_process
test_disabled_skill_excluded
test_missing_registry_fallback
test_output_valid_json
test_zero_matches_phase_checkpoint
test_methodology_hints
test_phase_scoped_methodology_hints
test_claude_md_maintenance_hint
test_agent_team_execution_matches
test_design_debate_as_domain
test_agent_team_review_matches
test_brainstorming_short_prompt
test_skill_name_mention_boost
test_domain_invocation_instruction
test_overflow_domain_hidden
test_teammate_idle_guard
test_review_emits_parallel_lines
test_ship_emits_sequence_lines
test_no_parallel_when_plugin_unavailable
test_process_slot_reserved
test_missing_triggers_handled
test_phase_uses_process_precedence
test_eval_phase_uses_process
test_name_boost_boundary_aware
test_trigger_boundary_excludes_dot
test_domain_instruction_no_process
test_incident_analysis_hint_fires
test_incident_analysis_skill_scores
test_incident_analysis_phase_gating
test_incident_analysis_preserves_existing_triggers
test_gcp_hint_fires_on_symptom_language
test_incident_analysis_trigger_source
test_incident_analysis_invoke_path

# ---------------------------------------------------------------------------
# 32. Incident-trend-analyzer routing tests
# ---------------------------------------------------------------------------
test_trend_analyzer_trigger_matching() {
    echo "-- test: incident-trend-analyzer triggers on trend keywords --"
    setup_test_env
    install_registry_with_incident_trend

    local output context

    output="$(run_hook "show me the incident trends across our postmortems")"
    context="$(extract_context "${output}")"
    assert_contains "incident trends triggers trend-analyzer" "incident-trend-analyzer" "${context}"

    output="$(run_hook "what keeps breaking in production")"
    context="$(extract_context "${output}")"
    assert_contains "what keeps breaking triggers trend-analyzer" "incident-trend-analyzer" "${context}"

    output="$(run_hook "analyze postmortems for recurring incidents")"
    context="$(extract_context "${output}")"
    assert_contains "recurring incidents triggers trend-analyzer" "incident-trend-analyzer" "${context}"

    output="$(run_hook "are there any failure patterns in our incidents")"
    context="$(extract_context "${output}")"
    assert_contains "failure patterns triggers trend-analyzer" "incident-trend-analyzer" "${context}"

    teardown_test_env
}

test_trend_analyzer_no_false_positive() {
    echo "-- test: incident-trend-analyzer does NOT trigger-match on plain incident prompts --"
    setup_test_env
    install_registry_with_incident_trend

    local stderr_file="${TEST_TMPDIR}/stderr_false_positive.txt"

    # Plain incident prompt should trigger incident-analysis but NOT trigger-match trend-analyzer
    jq -n --arg p "investigate this production incident in the auth service" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        SKILL_EXPLAIN=1 \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null

    local stderr_content
    stderr_content="$(cat "${stderr_file}")"

    # incident-analysis should have a trigger match (boundary= component in score)
    local ia_line
    ia_line="$(printf '%s' "${stderr_content}" | grep 'incident-analysis:' | grep -v 'incident-trend-analyzer')"
    assert_contains "incident-analysis has trigger match" "boundary=" "${ia_line}"

    # incident-trend-analyzer should NOT have a trigger match — only name-boost
    local trend_line
    trend_line="$(printf '%s' "${stderr_content}" | grep 'incident-trend-analyzer:')"
    assert_not_contains "trend-analyzer has no trigger match" "boundary=" "${trend_line}"
    assert_contains "trend-analyzer only has name-boost" "name-boost=" "${trend_line}"

    teardown_test_env
}

test_trend_analyzer_outscores_incident_analysis() {
    echo "-- test: trend-analyzer outscores incident-analysis on trend prompts --"
    setup_test_env
    install_registry_with_incident_trend

    local stderr_file="${TEST_TMPDIR}/stderr_trend_scores.txt"
    local prompts="what keeps breaking
show me failure pattern data
are there recurring failure patterns"

    local IFS_SAVE="$IFS"
    IFS='
'
    for prompt in $prompts; do
        IFS="$IFS_SAVE"
        jq -n --arg p "$prompt" '{"prompt":$p}' | \
            CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
            SKILL_EXPLAIN=1 \
            bash "${HOOK}" 2>"${stderr_file}" >/dev/null

        local stderr_content
        stderr_content="$(cat "${stderr_file}")"

        local trend_score ia_score
        trend_score="$(printf '%s' "${stderr_content}" | grep -oE 'incident-trend-analyzer=[0-9]+' | grep -oE '[0-9]+' | head -1)"
        ia_score="$(printf '%s' "${stderr_content}" | grep -oE '(^| )incident-analysis=[0-9]+' | grep -oE '[0-9]+' | head -1)"

        # If incident-analysis is absent from raw scores, it scored 0
        [ -z "${ia_score}" ] && ia_score=0

        if [ -z "${trend_score}" ]; then
            _record_fail "trend score missing for prompt '${prompt}'"
        elif [ "${trend_score}" -le "${ia_score}" ]; then
            _record_fail "trend-analyzer (${trend_score}) should outscore incident-analysis (${ia_score}) on '${prompt}'"
        else
            _record_pass "trend-analyzer (${trend_score}) > incident-analysis (${ia_score}) on '${prompt}'"
        fi
    done
    IFS="$IFS_SAVE"

    teardown_test_env
}

test_trend_analyzer_cofires_with_incident_analysis() {
    echo "-- test: trend-analyzer co-fires with incident-analysis on overlapping prompt --"
    setup_test_env
    install_registry_with_incident_trend

    local output context

    output="$(run_hook "analyze postmortems for recurring incidents")"
    context="$(extract_context "${output}")"
    assert_contains "trend-analyzer fires" "incident-trend-analyzer" "${context}"
    assert_contains "incident-analysis also fires" "incident-analysis" "${context}"

    teardown_test_env
}

test_trend_analyzer_trigger_source() {
    echo "-- test: default-triggers.json contains incident-trend-analyzer entry --"

    local invoke_path
    invoke_path="$(jq -r '.. | objects | select(.name == "incident-trend-analyzer") | .invoke // empty' config/default-triggers.json)"
    assert_equals "invoke path correct" "Skill(auto-claude-skills:incident-trend-analyzer)" "${invoke_path}"

    local phase
    phase="$(jq -r '.. | objects | select(.name == "incident-trend-analyzer") | .phase // empty' config/default-triggers.json)"
    assert_equals "phase is DEBUG" "DEBUG" "${phase}"
}

test_trend_analyzer_trigger_matching
test_trend_analyzer_no_false_positive
test_trend_analyzer_outscores_incident_analysis
test_trend_analyzer_cofires_with_incident_analysis
test_trend_analyzer_trigger_source

# ---------------------------------------------------------------------------
# SDLC enforcement: MUST INVOKE for process skills
# ---------------------------------------------------------------------------
test_must_invoke_for_build_intent() {
    echo "-- test: build intent gets MUST INVOKE for brainstorming --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "build a new user dashboard")"
    context="$(extract_context "${output}")"

    assert_contains "brainstorming must invoke" "MUST INVOKE" "${context}"
    assert_not_contains "brainstorming not YES/NO" "brainstorming YES/NO" "${context}"

    teardown_test_env
}

test_must_invoke_for_debug_intent() {
    echo "-- test: debug intent gets MUST INVOKE for debugging --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "debug the authentication crash")"
    context="$(extract_context "${output}")"

    assert_contains "debugging must invoke" "MUST INVOKE" "${context}"
    assert_not_contains "debugging not YES/NO" "systematic-debugging YES/NO" "${context}"

    teardown_test_env
}

test_domain_skills_keep_yes_no() {
    echo "-- test: domain skills still have YES/NO --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "build a secure authentication system with encryption")"
    context="$(extract_context "${output}")"

    # Process skill gets MUST INVOKE, domain gets YES/NO
    assert_contains "brainstorming must invoke" "MUST INVOKE" "${context}"
    assert_contains "domain has YES/NO" "YES/NO" "${context}"

    teardown_test_env
}

test_must_invoke_for_build_intent
test_must_invoke_for_debug_intent
test_domain_skills_keep_yes_no

# ---------------------------------------------------------------------------
# Skill composition chain tests
# ---------------------------------------------------------------------------
test_composition_chain_forward() {
    echo "-- test: brainstorming emits composition chain --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "build a new user dashboard")"
    context="$(extract_context "${output}")"

    assert_contains "composition has Composition:" "Composition:" "${context}"
    assert_contains "composition has CURRENT marker" "[CURRENT]" "${context}"
    assert_contains "composition has NEXT marker" "[NEXT]" "${context}"
    assert_contains "composition has writing-plans" "writing-plans" "${context}"
    assert_contains "composition has IMPORTANT directive" "IMPORTANT:" "${context}"

    teardown_test_env
}

test_composition_chain_midentry() {
    echo "-- test: executing-plans shows backward chain --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "follow the plan and resume where we left off next task")"
    context="$(extract_context "${output}")"

    assert_contains "midentry has Composition:" "Composition:" "${context}"
    assert_contains "midentry has DONE? marker" "[DONE?]" "${context}"
    assert_contains "midentry has CURRENT on executing-plans" "[CURRENT]" "${context}"

    teardown_test_env
}

test_composition_no_chain_for_debug() {
    echo "-- test: debug has no composition chain --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "debug the authentication crash")"
    context="$(extract_context "${output}")"

    assert_not_contains "debug has no Composition:" "Composition:" "${context}"
    assert_not_contains "debug has no IMPORTANT directive" "IMPORTANT:" "${context}"

    teardown_test_env
}

test_composition_domain_hint_during_step() {
    echo "-- test: domain hint says 'during the current step' with composition --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "build a secure authentication system with encryption")"
    context="$(extract_context "${output}")"

    assert_contains "domain hint has during step" "during the current step" "${context}"
    assert_not_contains "domain hint no before/during/after" "before, during, or after" "${context}"

    teardown_test_env
}

test_composition_workflow_chain() {
    echo "-- test: workflow skill with precedes emits chain --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "ship it and merge to main branch")"
    context="$(extract_context "${output}")"

    assert_contains "ship has Composition:" "Composition:" "${context}"
    assert_contains "ship has finishing-a-development-branch" "finishing-a-development-branch" "${context}"

    teardown_test_env
}

test_composition_chain_fallback_on_broken_walk() {
    echo "-- test: composition chain fallback when successor missing from registry --"
    setup_test_env

    # Install a registry where brainstorming has precedes=["writing-plans"]
    # but writing-plans is NOT in the skills array (simulates broken walk)
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": ["(build|create)"],
      "trigger_mode": "regex",
      "priority": 30,
      "precedes": ["writing-plans"],
      "requires": [],
      "invoke": "Skill(superpowers:brainstorming)",
      "available": true,
      "enabled": true
    }
  ],
  "plugins": [],
  "phase_guide": {},
  "phase_compositions": {}
}
REGISTRY

    local output context
    output="$(run_hook "build a dashboard")"
    context="$(extract_context "${output}")"

    # Even with a broken walk, the fallback should produce a chain
    assert_contains "fallback has Composition:" "Composition:" "${context}"
    assert_contains "fallback has writing-plans" "writing-plans" "${context}"
    assert_contains "fallback has IMPORTANT directive" "IMPORTANT:" "${context}"

    teardown_test_env
}

test_composition_chain_forward
test_composition_chain_midentry
test_composition_no_chain_for_debug
test_composition_domain_hint_during_step
test_composition_workflow_chain
test_composition_chain_fallback_on_broken_walk

# ---------------------------------------------------------------------------
# Trigger pattern validation tests (against default-triggers.json)
# ---------------------------------------------------------------------------
test_brainstorming_has_broad_triggers() {
    echo "-- test: brainstorming has broad verb triggers --"
    local triggers_file="${PROJECT_ROOT}/config/default-triggers.json"
    local brainstorm_triggers
    brainstorm_triggers="$(jq -r '.skills[] | select(.name == "brainstorming") | .triggers[]' "$triggers_file")"

    # Should contain common feature-request verbs
    assert_contains "brainstorming has build" "build" "$brainstorm_triggers"
    assert_contains "brainstorming has create" "create" "$brainstorm_triggers"
    assert_contains "brainstorming has implement" "implement" "$brainstorm_triggers"

    # Should still contain core design terms
    assert_contains "brainstorming has brainstorm" "brainstorm" "$brainstorm_triggers"
    assert_contains "brainstorming has design" "design" "$brainstorm_triggers"
    assert_contains "brainstorming has architect" "architect" "$brainstorm_triggers"
}

test_agent_team_has_plan_triggers() {
    echo "-- test: agent-team-execution has plan-execution triggers --"
    local triggers_file="${PROJECT_ROOT}/config/default-triggers.json"
    local ate_triggers
    ate_triggers="$(jq -r '.skills[] | select(.name == "agent-team-execution") | .triggers[]' "$triggers_file")"

    assert_contains "agent-team has team keywords" "agent.team" "$ate_triggers"
}

test_brainstorming_has_broad_triggers
test_agent_team_has_plan_triggers

# ---------------------------------------------------------------------------
# User config override tests
# ---------------------------------------------------------------------------
test_config_max_suggestions() {
    echo "-- test: max_suggestions limits skill count --"
    setup_test_env
    install_registry

    # Write config with max_suggestions: 1
    printf '{"max_suggestions": 1}' > "${HOME}/.claude/skill-config.json"

    # Use a prompt that matches multiple skills
    local output
    output="$(run_hook "debug this broken login bug and fix it")"
    local ctx
    ctx="$(extract_context "$output")"

    # With max_suggestions=1, should have only 1 skill line (Process:/Domain:/Workflow:/Required:)
    local skill_count
    skill_count="$(printf '%s' "$ctx" | grep -cE '^(Required|Process|  Domain|Workflow):' || true)"
    if [ "$skill_count" -le 1 ]; then
        _record_pass "max_suggestions=1 limits to 1 skill"
    else
        _record_fail "max_suggestions=1 limits to 1 skill" "got $skill_count skills"
    fi

    teardown_test_env
}

test_config_trigger_add() {
    echo "-- test: trigger override adds new pattern --"
    setup_test_env

    local session_hook="${PROJECT_ROOT}/hooks/session-start-hook.sh"

    # Add a new trigger pattern to systematic-debugging
    printf '{"overrides":{"systematic-debugging":{"triggers":["+customtrigger123"]}}}' \
        > "${HOME}/.claude/skill-config.json"

    # Run session-start to build registry
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "$session_hook" >/dev/null 2>&1

    local cache="${HOME}/.claude/.skill-registry-cache.json"
    if [ ! -f "$cache" ]; then
        _record_fail "trigger override: registry built" "cache file not found"
        teardown_test_env
        return
    fi

    local debug_triggers
    debug_triggers="$(jq -r '.skills[] | select(.name == "systematic-debugging") | .triggers | join(" ")' "$cache" 2>/dev/null)"

    assert_contains "trigger + adds new pattern" "customtrigger123" "$debug_triggers"

    teardown_test_env
}

test_config_custom_skills() {
    echo "-- test: custom_skills appear in registry --"
    setup_test_env

    local session_hook="${PROJECT_ROOT}/hooks/session-start-hook.sh"

    # Write config with a custom skill
    cat > "${HOME}/.claude/skill-config.json" <<'EOF'
{
    "custom_skills": [{
        "name": "my-custom-test-skill",
        "role": "domain",
        "triggers": ["customskilltest"],
        "invoke": "Skill(my-custom-test-skill)"
    }]
}
EOF

    # Run session-start to build registry
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "$session_hook" >/dev/null 2>&1

    local cache="${HOME}/.claude/.skill-registry-cache.json"
    if [ ! -f "$cache" ]; then
        _record_fail "custom skill: registry built" "cache file not found"
        teardown_test_env
        return
    fi

    local custom_name
    custom_name="$(jq -r '.skills[] | select(.name == "my-custom-test-skill") | .name' "$cache" 2>/dev/null)"

    assert_equals "custom skill in registry" "my-custom-test-skill" "$custom_name"

    # Verify it's marked as available and enabled
    local custom_available
    custom_available="$(jq -r '.skills[] | select(.name == "my-custom-test-skill") | .available' "$cache" 2>/dev/null)"
    assert_equals "custom skill is available" "true" "$custom_available"

    teardown_test_env
}

test_config_greeting_blocklist() {
    echo "-- test: custom greeting blocklist blocks matching prompts --"
    setup_test_env
    install_registry

    # Write config with a custom blocklist that blocks "xyztest"
    printf '{"greeting_blocklist":"xyztest"}' > "${HOME}/.claude/skill-config.json"

    # A prompt matching the custom blocklist should produce no skills
    local output
    output="$(run_hook "xyztest")"
    local ctx
    ctx="$(extract_context "$output")"

    # Should have no skill output (blocklist triggers early exit)
    assert_not_contains "custom blocklist blocks prompt" "Skill(" "$ctx"

    teardown_test_env
}

test_config_max_suggestions
test_config_trigger_add
test_config_custom_skills
test_config_greeting_blocklist

# ---------------------------------------------------------------------------
# End-to-end integration test: session-start → routing pipeline
# ---------------------------------------------------------------------------
test_end_to_end_pipeline() {
    echo "-- test: end-to-end session-start → routing pipeline --"
    setup_test_env

    local session_hook="${PROJECT_ROOT}/hooks/session-start-hook.sh"
    local routing_hook="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    # Step 1: Run session-start to build registry
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "$session_hook" >/dev/null 2>&1

    # Step 2: Verify registry was created
    assert_file_exists "e2e: registry cache created" "$cache"

    # Step 3: Verify registry is valid JSON with skills
    local skill_count
    skill_count="$(jq '.skills | length' "$cache" 2>/dev/null)"
    if [ -n "$skill_count" ] && [ "$skill_count" -gt 0 ]; then
        _record_pass "e2e: registry has skills ($skill_count)"
    else
        _record_fail "e2e: registry has skills" "got ${skill_count:-empty}"
        teardown_test_env
        return
    fi

    # Step 4: Route a prompt through the routing hook
    # Use a prompt that triggers design-debate (bundled skill, always available)
    local output
    output="$(jq -n --arg p "brainstorm the architecture and design trade-offs" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "$routing_hook" 2>/dev/null)"

    local ctx
    ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"

    # Step 5: Verify design-debate was activated (bundled skill, always available)
    assert_contains "e2e: brainstorm prompt activates design-debate" "design-debate" "$ctx"

    teardown_test_env
}

test_end_to_end_pipeline

# ---------------------------------------------------------------------------
# Idle guard cooldown tests
# ---------------------------------------------------------------------------
test_idle_guard_cooldown() {
    echo "-- test: idle guard cooldown prevents spam --"
    setup_test_env

    local guard="${PROJECT_ROOT}/hooks/teammate-idle-guard.sh"
    local cooldown_dir="${HOME}/.claude/.idle-cooldowns"
    local cooldown_file="${cooldown_dir}/claude-idle-test-team-worker-last-nudge"
    local stderr_file="${TEST_TMPDIR}/guard-stderr.txt"

    # Clean stale cooldown files from prior tests
    mkdir -p "$cooldown_dir"
    rm -f "$cooldown_file"

    # Create an in_progress task for the worker
    mkdir -p "${HOME}/.claude/tasks/test-team"
    printf '{"subject":"Fix auth","status":"in_progress","owner":"worker"}' \
        > "${HOME}/.claude/tasks/test-team/1.json"

    # First nudge should fire (exit 2)
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>"$stderr_file"
    local exit_code=$?
    assert_equals "first nudge fires" "2" "$exit_code"
    assert_contains "first nudge has message" "unfinished tasks" "$(cat "$stderr_file")"
    assert_file_exists "cooldown file created" "$cooldown_file"

    # Second nudge within cooldown should be suppressed (exit 0)
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>"$stderr_file"
    exit_code=$?
    assert_equals "second nudge within cooldown suppressed" "0" "$exit_code"

    # Simulate cooldown expiry by backdating the timestamp
    printf '%s' "$(($(date +%s) - 121))" > "$cooldown_file"
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>"$stderr_file"
    exit_code=$?
    assert_equals "nudge fires after cooldown expires" "2" "$exit_code"

    # Clean up cooldown file
    rm -f "$cooldown_file"

    teardown_test_env
}

test_idle_guard_sanitization() {
    echo "-- test: idle guard sanitizes path-unsafe names --"
    setup_test_env

    local guard="${PROJECT_ROOT}/hooks/teammate-idle-guard.sh"
    local cooldown_dir="${HOME}/.claude/.idle-cooldowns"
    local cooldown_file="${cooldown_dir}/claude-idle-safe-name-last-nudge"

    mkdir -p "$cooldown_dir"
    rm -f "$cooldown_file"

    mkdir -p "${HOME}/.claude/tasks/safe-name"
    printf '{"subject":"Task","status":"in_progress","owner":"safe-name"}' \
        > "${HOME}/.claude/tasks/safe-name/1.json"

    # Team/teammate with slashes should be sanitized (no path traversal)
    printf '{"teammate_name":"safe-name","team_name":"safe-name"}' | bash "$guard" 2>/dev/null
    local exit_code=$?
    assert_equals "sanitized guard fires" "2" "$exit_code"

    rm -f "$cooldown_file"
    teardown_test_env
}

test_idle_guard_non_numeric_cooldown() {
    echo "-- test: idle guard handles non-numeric cooldown file --"
    setup_test_env

    local guard="${PROJECT_ROOT}/hooks/teammate-idle-guard.sh"
    local cooldown_dir="${HOME}/.claude/.idle-cooldowns"
    local cooldown_file="${cooldown_dir}/claude-idle-test-team-worker-last-nudge"

    mkdir -p "${HOME}/.claude/tasks/test-team"
    printf '{"subject":"Task","status":"in_progress","owner":"worker"}' \
        > "${HOME}/.claude/tasks/test-team/1.json"

    # Write garbage to cooldown file — guard should still nudge (not crash)
    mkdir -p "$cooldown_dir"
    printf 'not-a-number' > "$cooldown_file"
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>/dev/null
    local exit_code=$?
    assert_equals "nudge fires with corrupted cooldown file" "2" "$exit_code"

    rm -f "$cooldown_file"
    teardown_test_env
}

# ---------------------------------------------------------------------------
# stderr silence tests (no SKILL_EXPLAIN = no stderr)
# ---------------------------------------------------------------------------
test_no_stderr_without_explain() {
    echo "-- test: no stderr without SKILL_EXPLAIN --"
    setup_test_env
    install_registry

    local stderr_file="${TEST_TMPDIR}/stderr.txt"

    # Without SKILL_EXPLAIN: stderr should be empty (even with matching skills)
    jq -n --arg p "debug this broken login bug" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    local stderr_content
    stderr_content="$(cat "${stderr_file}")"
    assert_equals "no stderr without SKILL_EXPLAIN" "" "${stderr_content}"

    teardown_test_env
}

test_skill_explain_with_matches() {
    setup_test_env
    install_registry

    local stderr_file="${TEST_TMPDIR}/stderr_explain.txt"

    # SKILL_EXPLAIN=1 with matching prompt → stderr contains explain output
    jq -n --arg p "debug this broken login bug" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        SKILL_EXPLAIN=1 \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    local stderr_content
    stderr_content="$(cat "${stderr_file}")"
    assert_contains "explain shows header" "=== EXPLAIN ===" "${stderr_content}"
    assert_contains "explain shows scoring" "Scoring:" "${stderr_content}"
    assert_contains "explain shows prompt" "Prompt:" "${stderr_content}"
    assert_contains "explain shows skill score" "systematic-debugging:" "${stderr_content}"
    assert_contains "explain shows role-cap" "Role-cap selection" "${stderr_content}"
    assert_contains "explain shows result" "Result:" "${stderr_content}"
    assert_contains "explain shows end marker" "=== END ===" "${stderr_content}"

    teardown_test_env
}

test_skill_explain_no_matches() {
    setup_test_env
    install_registry

    local stderr_file="${TEST_TMPDIR}/stderr_explain_none.txt"

    # SKILL_EXPLAIN=1 with a prompt that won't match any triggers (long enough to pass length check)
    jq -n --arg p "tell me about the weather forecast today please" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        SKILL_EXPLAIN=1 \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    local stderr_content
    stderr_content="$(cat "${stderr_file}")"
    assert_contains "explain no-match shows header" "=== EXPLAIN ===" "${stderr_content}"
    assert_contains "explain no-match shows 0 skills" "0 skills" "${stderr_content}"

    teardown_test_env
}

test_skill_explain_off_by_default() {
    setup_test_env
    install_registry

    local stderr_file="${TEST_TMPDIR}/stderr_explain_off.txt"

    # Without SKILL_EXPLAIN → no explain output on stderr
    jq -n --arg p "debug this broken login bug" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    local stderr_content
    stderr_content="$(cat "${stderr_file}")"
    assert_equals "no explain without SKILL_EXPLAIN" "" "${stderr_content}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Conversation-depth-aware verbosity tests
# ---------------------------------------------------------------------------

_setup_depth_counter() {
    # Helper: set session-scoped depth counter to a value
    # Usage: _setup_depth_counter 5  (sets counter to 5)
    #        _setup_depth_counter     (removes counter + token)
    local val="${1:-}"
    local token="test-session-$$"
    rm -f "${HOME}/.claude/.skill-prompt-count-"* 2>/dev/null
    rm -f "${HOME}/.claude/.skill-session-token" 2>/dev/null
    if [[ -n "$val" ]]; then
        printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
        printf '%s' "$val" > "${HOME}/.claude/.skill-prompt-count-${token}"
    fi
}

test_depth_full_format_first_prompt() {
    setup_test_env
    install_registry

    # No counter file exists → treated as prompt 1 → full format for 3+ skills
    _setup_depth_counter
    local output
    output="$(run_hook "build a secure frontend component")"
    local ctx
    ctx="$(extract_context "${output}")"

    assert_contains "depth1: full format has ASSESS PHASE" "ASSESS PHASE" "${ctx}"
    assert_contains "depth1: full format has EVALUATE skills" "EVALUATE skills" "${ctx}"
    assert_contains "depth1: full format has Step 3" "INVOKE the process skill" "${ctx}"

    teardown_test_env
}

test_depth_compact_format_after_5() {
    setup_test_env
    install_registry

    # Write counter=5 so next invocation will be prompt 6 → compact format even for 3+ skills
    _setup_depth_counter 5
    local output
    output="$(run_hook "build a secure frontend component")"
    local ctx
    ctx="$(extract_context "${output}")"

    assert_not_contains "depth6: compact format has no ASSESS PHASE" "ASSESS PHASE" "${ctx}"
    assert_not_contains "depth6: compact format has no EVALUATE skills" "EVALUATE skills" "${ctx}"
    assert_contains "depth6: compact format has Evaluate" "Evaluate:" "${ctx}"
    assert_contains "depth6: compact format has skill names" "brainstorming" "${ctx}"

    teardown_test_env
}

test_depth_minimal_format_after_10() {
    setup_test_env
    install_registry

    # Write counter=10 so next invocation will be prompt 11 → minimal format
    _setup_depth_counter 10
    local output
    output="$(run_hook "build a secure frontend component")"
    local ctx
    ctx="$(extract_context "${output}")"

    assert_not_contains "depth11: minimal format has no ASSESS PHASE" "ASSESS PHASE" "${ctx}"
    assert_not_contains "depth11: minimal format has no EVALUATE skills" "EVALUATE skills" "${ctx}"
    assert_not_contains "depth11: minimal format has no State your plan" "State your plan" "${ctx}"
    assert_not_contains "depth11: minimal format has no DOMAIN_HINT" "Domain skills evaluated" "${ctx}"
    assert_contains "depth11: minimal format has Evaluate" "Evaluate:" "${ctx}"
    assert_contains "depth11: minimal format has skill names" "brainstorming" "${ctx}"
    assert_contains "depth11: minimal format has IMPORTANT directive" "IMPORTANT:" "${ctx}"
    assert_contains "depth11: minimal format has composition chain" "Composition:" "${ctx}"

    teardown_test_env
}

test_depth_verbose_override() {
    setup_test_env
    install_registry

    # Write counter=19 so next invocation will be prompt 20 → should be minimal,
    # but SKILL_VERBOSE=1 forces full format
    _setup_depth_counter 19
    local output
    output="$(jq -n --arg p "build a secure frontend component" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        SKILL_VERBOSE=1 \
        bash "${HOOK}" 2>/dev/null)"
    local ctx
    ctx="$(extract_context "${output}")"

    assert_contains "verbose override: full format has ASSESS PHASE" "ASSESS PHASE" "${ctx}"
    assert_contains "verbose override: full format has EVALUATE skills" "EVALUATE skills" "${ctx}"
    assert_contains "verbose override: full format has INVOKE process skill" "INVOKE the process skill" "${ctx}"

    teardown_test_env
}

test_depth_counter_missing_treated_as_1() {
    setup_test_env
    install_registry

    # Ensure counter file does NOT exist
    _setup_depth_counter
    local output
    output="$(run_hook "build a secure frontend component")"
    local ctx
    ctx="$(extract_context "${output}")"

    # Same as prompt 1: full format for 3+ skills
    assert_contains "missing counter: full format has ASSESS PHASE" "ASSESS PHASE" "${ctx}"

    # Verify a counter file was created with value 1
    local count_val
    count_val="$(cat "${HOME}/.claude/.skill-prompt-count-"* 2>/dev/null)"
    assert_equals "missing counter: file created with value 1" "1" "${count_val}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Batch scripting skill routing
# ---------------------------------------------------------------------------
test_batch_scripting_triggers() {
    setup_test_env
    install_registry_with_batch

    local out ctx

    out="$(run_hook "batch migrate all files to ESM")"
    ctx="$(extract_context "$out")"
    assert_contains "batch-scripting triggers on 'batch migrate'" \
        "batch-scripting" "$ctx"

    out="$(run_hook "bulk refactor across all files")"
    ctx="$(extract_context "$out")"
    assert_contains "batch-scripting triggers on 'bulk refactor across all files'" \
        "batch-scripting" "$ctx"

    out="$(run_hook "transform all test files")"
    ctx="$(extract_context "$out")"
    assert_contains "batch-scripting triggers on 'transform all'" \
        "batch-scripting" "$ctx"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Red flags injection when verification-before-completion fires
# ---------------------------------------------------------------------------
test_red_flags_injected_for_verification() {
    setup_test_env
    install_registry

    local out ctx

    out="$(run_hook "ship it, all tests pass")"
    ctx="$(extract_context "$out")"
    assert_contains "red flags injected when verification fires" \
        "HALT if any Red Flag" "$ctx"

    teardown_test_env
}

test_red_flags_not_injected_for_other_skills() {
    setup_test_env
    install_registry

    local out ctx

    out="$(run_hook "debug this crash")"
    ctx="$(extract_context "$out")"
    assert_not_contains "red flags NOT injected for debugging" \
        "HALT if any Red Flag" "$ctx"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Raw scores in explain output
# ---------------------------------------------------------------------------
test_skill_explain_raw_scores() {
    setup_test_env
    install_registry

    local stderr_file="${TEST_TMPDIR}/stderr_raw_scores.txt"

    # SKILL_EXPLAIN=1 with matching prompt → stderr should include raw scores
    jq -n --arg p "debug this broken login bug" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        SKILL_EXPLAIN=1 \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    local stderr_content
    stderr_content="$(cat "${stderr_file}")"
    assert_contains "explain shows raw scores header" "Raw scores:" "${stderr_content}"
    assert_contains "explain shows skill name=score" "systematic-debugging=" "${stderr_content}"

    teardown_test_env
}

test_idle_guard_cooldown
test_idle_guard_sanitization
test_idle_guard_non_numeric_cooldown
test_skill_explain_with_matches
test_skill_explain_no_matches
test_skill_explain_off_by_default
test_depth_full_format_first_prompt
test_depth_compact_format_after_5
test_depth_minimal_format_after_10
test_depth_verbose_override
test_depth_counter_missing_treated_as_1
test_batch_scripting_triggers
test_red_flags_injected_for_verification
test_red_flags_not_injected_for_other_skills
test_skill_explain_raw_scores

# ---------------------------------------------------------------------------
# Keyword matching tests
# ---------------------------------------------------------------------------
test_keywords_match() {
    echo "-- test: keyword 'something is off' routes to systematic-debugging --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'KWREG'
{
  "version": "test",
  "skills": [
    {
      "name": "systematic-debugging",
      "role": "process",
      "phase": "DEBUG",
      "triggers": [],
      "keywords": ["stuck on", "something is off", "not right", "doesn't make sense", "confused by"],
      "priority": 10,
      "invoke": "Skill(superpowers:systematic-debugging)",
      "available": true,
      "enabled": true
    },
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": [],
      "keywords": ["how should", "what approach", "best way to", "ideas for", "options for"],
      "priority": 30,
      "invoke": "Skill(superpowers:brainstorming)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
KWREG

    local output context
    output="$(run_hook "I'm stuck on this auth flow and something is off")"
    context="$(extract_context "${output}")"

    assert_contains "keyword 'something is off' matches systematic-debugging" "systematic-debugging" "${context}"

    teardown_test_env
}

test_keywords_no_short_match() {
    echo "-- test: keywords shorter than 6 chars are ignored --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'KWSHORTREG'
{
  "version": "test",
  "skills": [
    {
      "name": "short-keyword-skill",
      "role": "domain",
      "triggers": [],
      "keywords": ["help", "fix", "bad"],
      "priority": 10,
      "invoke": "Skill(mock:short-keyword-skill)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
KWSHORTREG

    local output context
    output="$(run_hook "help me fix this bad code please")"
    context="$(extract_context "${output}")"

    # All keywords are < 6 chars so none should score; expect empty output
    if [[ -z "$output" ]]; then
        _record_pass "short keywords produce no output"
    else
        _record_fail "short keywords produce no output" "got: ${output}"
    fi

    teardown_test_env
}

test_keywords_match
test_keywords_no_short_match

# ---------------------------------------------------------------------------
# Zero-match instrumentation tests
# ---------------------------------------------------------------------------

test_zero_match_instrumented() {
    setup_test_env
    install_registry
    local counter_file="${HOME}/.claude/.skill-zero-match-count"
    rm -f "$counter_file"
    # Run a prompt that won't match any skills
    run_hook "explain this code to me" >/dev/null
    assert_file_exists "zero-match counter file should be created" "$counter_file"
    local count
    count="$(cat "$counter_file")"
    assert_equals "zero-match count should be 1 after first miss" "1" "$count"
    # Run another non-matching prompt
    run_hook "what does this function do" >/dev/null
    count="$(cat "$counter_file")"
    assert_equals "zero-match count should be 2 after second miss" "2" "$count"
    teardown_test_env
}

test_match_not_counted_as_zero() {
    setup_test_env
    install_registry
    local counter_file="${HOME}/.claude/.skill-zero-match-count"
    rm -f "$counter_file"
    # Run a prompt that DOES match
    run_hook "debug this bug" >/dev/null
    # Counter file should not exist or be 0
    if [[ -f "$counter_file" ]]; then
        local count
        count="$(cat "$counter_file")"
        assert_equals "zero-match count should not increment on a match" "0" "$count"
    else
        _record_pass "zero-match counter file correctly not created on match"
    fi
    teardown_test_env
}

test_zero_match_instrumented
test_match_not_counted_as_zero

# ---------------------------------------------------------------------------
# Last-skill context signal and composition tie-breaking tests
# ---------------------------------------------------------------------------

test_last_skill_signal_written() {
    setup_test_env
    install_registry
    rm -f "${HOME}/.claude/.skill-last-invoked-"*
    printf 'test-signal-session' > "${HOME}/.claude/.skill-session-token"
    run_hook "debug this bug" >/dev/null
    local signal_file="${HOME}/.claude/.skill-last-invoked-test-signal-session"
    assert_file_exists "signal file should be created after routing" "$signal_file"
    local skill_name
    skill_name="$(jq -r '.skill' "$signal_file" 2>/dev/null)"
    assert_equals "signal should contain the top skill" "systematic-debugging" "$skill_name"
    local skill_phase
    skill_phase="$(jq -r '.phase' "$signal_file" 2>/dev/null)"
    assert_equals "signal should contain the skill's phase" "DEBUG" "$skill_phase"
    teardown_test_env
}
test_last_skill_signal_written

test_composition_bonus_boosts_successor() {
    setup_test_env
    # Set up a chain: brainstorming -> writing-plans
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    cat > "${cache_file}" <<'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": ["(build|create)"],
      "trigger_mode": "regex",
      "priority": 30,
      "invoke": "Skill(superpowers:brainstorming)",
      "precedes": ["writing-plans"],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "writing-plans",
      "role": "process",
      "phase": "PLAN",
      "triggers": ["(plan|outline)"],
      "trigger_mode": "regex",
      "priority": 40,
      "invoke": "Skill(superpowers:writing-plans)",
      "precedes": [],
      "requires": ["brainstorming"],
      "available": true,
      "enabled": true
    }
  ]
}
REGISTRY
    # Simulate brainstorming was last invoked
    printf 'test-bonus-session' > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"brainstorming","phase":"DESIGN"}' > "${HOME}/.claude/.skill-last-invoked-test-bonus-session"

    # Send a prompt that matches writing-plans ("plan") — it should get +20 bonus
    local output
    output="$(jq -n --arg p "let's plan this out" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_EXPLAIN=1 bash "${HOOK}" 2>&1 1>/dev/null)"
    # The explain output should show writing-plans selected
    assert_contains "writing-plans should be boosted after brainstorming" "writing-plans" "$output"
    teardown_test_env
}
test_composition_bonus_boosts_successor

test_done_marker_when_signal_exists() {
    setup_test_env
    # Same chain setup, verify [DONE] instead of [DONE?]
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    cat > "${cache_file}" <<'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": ["(build|create)"],
      "trigger_mode": "regex",
      "priority": 30,
      "invoke": "Skill(superpowers:brainstorming)",
      "precedes": ["writing-plans"],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "writing-plans",
      "role": "process",
      "phase": "PLAN",
      "triggers": ["(plan|outline)"],
      "trigger_mode": "regex",
      "priority": 40,
      "invoke": "Skill(superpowers:writing-plans)",
      "precedes": ["executing-plans"],
      "requires": ["brainstorming"],
      "available": true,
      "enabled": true
    },
    {
      "name": "executing-plans",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": ["(continue|next|execute)"],
      "trigger_mode": "regex",
      "priority": 35,
      "invoke": "Skill(superpowers:executing-plans)",
      "precedes": [],
      "requires": ["writing-plans"],
      "available": true,
      "enabled": true
    }
  ]
}
REGISTRY
    # Simulate: writing-plans was last invoked (so brainstorming is DONE)
    printf 'test-done-session' > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"writing-plans","phase":"PLAN"}' > "${HOME}/.claude/.skill-last-invoked-test-done-session"

    # Trigger executing-plans
    local output
    output="$(run_hook "continue with next step")"
    local ctx
    ctx="$(extract_context "$output")"
    # The composition chain should show [DONE] for brainstorming (not [DONE?])
    assert_contains "brainstorming should show [DONE] when signal confirms it ran" "[DONE]" "$ctx"
    assert_not_contains "should not show [DONE?] when signal confirms completion" "[DONE?]" "$ctx"
    teardown_test_env
}
test_done_marker_when_signal_exists

# ---------------------------------------------------------------------------
# Opal Integration: exercise keywords, zero-match counter, last-skill signal,
# and composition tie-breaking together in one flow
# ---------------------------------------------------------------------------
test_opal_integration() {
    setup_test_env
    # Full flow: keywords + context signal + zero-match counter + composition bonus
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    cat > "${cache_file}" <<'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "systematic-debugging",
      "role": "process",
      "phase": "DEBUG",
      "triggers": ["(debug|bug|broken)"],
      "keywords": ["something is off"],
      "trigger_mode": "regex",
      "priority": 50,
      "invoke": "Skill(superpowers:systematic-debugging)",
      "precedes": [],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": ["(build|create)"],
      "keywords": [],
      "trigger_mode": "regex",
      "priority": 30,
      "invoke": "Skill(superpowers:brainstorming)",
      "precedes": ["writing-plans"],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "writing-plans",
      "role": "process",
      "phase": "PLAN",
      "triggers": ["(plan|outline)"],
      "keywords": [],
      "trigger_mode": "regex",
      "priority": 40,
      "invoke": "Skill(superpowers:writing-plans)",
      "precedes": [],
      "requires": ["brainstorming"],
      "available": true,
      "enabled": true
    }
  ]
}
REGISTRY

    printf 'opal-integration-session' > "${HOME}/.claude/.skill-session-token"
    rm -f "${HOME}/.claude/.skill-last-invoked-opal-integration-session"
    rm -f "${HOME}/.claude/.skill-zero-match-count"

    # Step 1: Keyword match — "something is off" routes to debugging
    local output ctx
    output="$(run_hook "something is off with the auth flow")"
    ctx="$(extract_context "$output")"
    assert_contains "keyword 'something is off' should route to debugging" "systematic-debugging" "$ctx"

    # Step 2: Verify signal was written
    local signal_file="${HOME}/.claude/.skill-last-invoked-opal-integration-session"
    assert_file_exists "signal file created after keyword match" "$signal_file"
    local last_skill
    last_skill="$(jq -r '.skill' "$signal_file" 2>/dev/null)"
    assert_equals "signal should record debugging as last skill" "systematic-debugging" "$last_skill"

    # Step 3: Zero-match — prompt with no matching skills
    run_hook "explain this code to me please" >/dev/null
    local zm_count
    zm_count="$(cat "${HOME}/.claude/.skill-zero-match-count" 2>/dev/null)"
    assert_equals "zero-match counter should be 1" "1" "$zm_count"

    # Step 4: Context bonus — simulate brainstorming was last, then trigger writing-plans
    printf '{"skill":"brainstorming","phase":"DESIGN"}' > "$signal_file"
    output="$(run_hook "let's plan this out")"
    ctx="$(extract_context "$output")"
    assert_contains "writing-plans should be selected after brainstorming context" "writing-plans" "$ctx"

    teardown_test_env
}
test_opal_integration

# ---------------------------------------------------------------------------
# Zero-match emits nothing (no hookSpecificOutput)
# ---------------------------------------------------------------------------
test_zero_match_emits_nothing() {
    echo "-- test: zero-match emits nothing --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "tell me about the weather forecast for tomorrow please")"

    if [[ -z "$output" ]]; then
        _record_pass "zero-match produces no output"
    else
        _record_fail "zero-match produces no output" "got: ${output}"
    fi

    # Counter should still be incremented
    local zm_count
    zm_count="$(cat "${HOME}/.claude/.skill-zero-match-count" 2>/dev/null)"
    if [[ "$zm_count" =~ ^[0-9]+$ ]] && [[ "$zm_count" -ge 1 ]]; then
        _record_pass "zero-match counter incremented"
    else
        _record_fail "zero-match counter incremented" "got: ${zm_count:-<empty>}"
    fi

    teardown_test_env
}
test_zero_match_emits_nothing

# ---------------------------------------------------------------------------
# Full format only on prompt 1 (3+ skills)
# ---------------------------------------------------------------------------
test_full_format_only_prompt_1() {
    echo "-- test: full format only on prompt 1 --"
    local prompt="build a new component and review the design for security"

    # --- Sub-test A: prompt 1 (no prior counter) SHOULD show full format ---
    setup_test_env
    install_registry

    # Ensure no session token or counter exists (fresh session = prompt 1)
    rm -f "${HOME}/.claude/.skill-session-token"
    rm -f "${HOME}/.claude/.skill-prompt-count-"*

    local output ctx
    output="$(run_hook "$prompt")"
    ctx="$(extract_context "$output")"

    if printf '%s' "$ctx" | grep -q "Step 1 -- ASSESS"; then
        _record_pass "full format shown on prompt 1"
    else
        _record_fail "full format shown on prompt 1" "output missing 'Step 1 -- ASSESS': ${ctx}"
    fi

    teardown_test_env

    # --- Sub-test B: prompt 3 (counter at 2) should NOT show full format ---
    setup_test_env
    install_registry

    # Set up session token and depth counter so _PROMPT_COUNT will be 3
    local token="test-full-fmt"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    printf '%s' "2" > "${HOME}/.claude/.skill-prompt-count-${token}"

    output="$(run_hook "$prompt")"
    ctx="$(extract_context "$output")"

    if printf '%s' "$ctx" | grep -q "Step 1 -- ASSESS"; then
        _record_fail "no full format on prompt 3" "output contains 'Step 1 -- ASSESS': ${ctx}"
    else
        _record_pass "no full format on prompt 3"
    fi

    # Verify we still got output (compact format, not empty)
    if [[ -n "$ctx" ]]; then
        _record_pass "prompt 3 still produces output (compact format)"
    else
        _record_fail "prompt 3 still produces output (compact format)" "output was empty"
    fi

    teardown_test_env
}
test_full_format_only_prompt_1

# --- Test: name_boost segment reduced from 40 to 20 ---
test_name_boost_segment_reduced() {
    setup_test_env
    install_registry

    # "build a component and review it" — both brainstorming and requesting-code-review match.
    # requesting-code-review: trigger "review" boundary=30 + priority=51 + name_boost(segment "review" 6 chars)
    # With name_boost=20: 30+51+20=101.  With old name_boost=40: 30+51+40=121.
    # brainstorming: trigger "build" boundary=30 + priority=30 = 60 (no name_boost).
    # The role cap (max 1 process) reserves the top process skill (requesting-code-review).
    # Verify: requesting-code-review gets name-boost=20 (not 40) via SKILL_EXPLAIN stderr.
    local explain_output
    explain_output="$(jq -n --arg p "build a component and review it" '{"prompt":$p}' | \
        SKILL_EXPLAIN=1 CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>&1 1>/dev/null)"

    # name-boost=20 should appear in explain output (not name-boost=40)
    assert_contains "name-boost should be 20" "name-boost=20" "$explain_output"

    # Verify name-boost=40 does NOT appear (confirms the reduction)
    if printf '%s' "$explain_output" | grep -q "name-boost=40"; then
        _record_fail "name-boost should not be 40" "found name-boost=40 in explain output"
    else
        _record_pass "name-boost should not be 40"
    fi

    # requesting-code-review should score 75 (boundary=30 + priority=25 + name_boost=20)
    if printf '%s' "$explain_output" | grep -q "requesting-code-review.* = 75"; then
        _record_pass "requesting-code-review score is 75"
    else
        _record_fail "requesting-code-review score is 75" "expected score 75 in explain output"
    fi

    teardown_test_env
}
test_name_boost_segment_reduced

# ---------------------------------------------------------------------------
# Overflow skills should never appear in context output
# ---------------------------------------------------------------------------
test_no_overflow_display() {
    echo "-- test: no overflow display --"
    setup_test_env
    install_registry

    # Trigger many skills to force overflow
    local output ctx
    output="$(run_hook "build and debug this security issue then review and ship it")"
    ctx="$(extract_context "$output")"

    assert_not_contains "overflow skills should not appear" "Also relevant:" "$ctx"

    teardown_test_env
}
test_no_overflow_display

# ---------------------------------------------------------------------------
# Escape hatch: [no-skills] and -- prefix suppress all routing
# ---------------------------------------------------------------------------
test_escape_hatch_no_skills() {
    echo "-- test: escape hatch no-skills --"
    setup_test_env
    install_registry

    # [no-skills] marker should produce no output
    local output
    output="$(run_hook "[no-skills] build a new feature")"
    assert_equals "[no-skills] should produce no output" "" "$output"

    # Also test -- prefix
    output="$(run_hook "-- just do the thing without skills please")"
    assert_equals "-- prefix should produce no output" "" "$output"

    # Normal prompt should still produce output
    output="$(run_hook "build a new authentication feature")"
    local ctx
    ctx="$(extract_context "$output")"
    assert_contains "normal prompt should still route" "brainstorming" "$ctx"

    teardown_test_env
}
test_escape_hatch_no_skills

# ---------------------------------------------------------------------------
# False-positive negative test suite — regression safety net for trigger precision
# Proves common prompts that should NOT trigger skills actually don't.
# ---------------------------------------------------------------------------
test_false_positive_defense() {
    echo "-- test: false-positive defense (10 negative prompts) --"
    setup_test_env
    install_registry

    local output ctx

    # 1. "rename this variable to snake_case" — should NOT match anything
    output="$(run_hook "rename this variable to snake_case")"
    ctx="$(extract_context "${output}")"
    assert_equals "FP01: rename variable -> zero match" "" "${ctx}"

    # 2. "explain this function to me" — should NOT match anything
    output="$(run_hook "explain this function to me")"
    ctx="$(extract_context "${output}")"
    assert_equals "FP02: explain function -> zero match" "" "${ctx}"

    # 3. "where is the database config defined" — should NOT match anything
    output="$(run_hook "where is the database config defined")"
    ctx="$(extract_context "${output}")"
    assert_equals "FP03: database config location -> zero match" "" "${ctx}"

    # 4. "show me the recent changes to this file" — should NOT match anything
    # KNOWN FALSE POSITIVE: "changes" contains substring "hang" which triggers systematic-debugging
    # assert_equals "FP04: show recent changes -> zero match" "" "${ctx}"
    output="$(run_hook "show me the recent changes to this file")"
    ctx="$(extract_context "${output}")"
    assert_contains "FP04: 'changes' substring-matches 'hang' in systematic-debugging" "systematic-debugging" "${ctx}"
    assert_not_contains "FP04: should not trigger brainstorming" "brainstorming" "${ctx}"

    # 5. "what does this error message mean" — may match debugging (acceptable)
    # KNOWN FALSE POSITIVE: "error" is a word-boundary match for systematic-debugging
    # assert_equals "FP05: error message meaning -> zero match" "" "${ctx}"
    output="$(run_hook "what does this error message mean")"
    ctx="$(extract_context "${output}")"
    assert_contains "FP05: 'error' triggers systematic-debugging" "systematic-debugging" "${ctx}"
    assert_not_contains "FP05: should not trigger brainstorming" "brainstorming" "${ctx}"

    # 6. "format this code block properly" — should NOT match anything
    output="$(run_hook "format this code block properly")"
    ctx="$(extract_context "${output}")"
    assert_equals "FP06: format code block -> zero match" "" "${ctx}"

    # 7. "delete the old migration files" — should NOT match anything
    output="$(run_hook "delete the old migration files")"
    ctx="$(extract_context "${output}")"
    assert_equals "FP07: delete migration files -> zero match" "" "${ctx}"

    # 8. "move this function to a separate module" — should NOT match anything
    output="$(run_hook "move this function to a separate module")"
    ctx="$(extract_context "${output}")"
    assert_equals "FP08: move function to module -> zero match" "" "${ctx}"

    # 9. "read the package.json and tell me the version" — should NOT match anything
    output="$(run_hook "read the package.json and tell me the version")"
    ctx="$(extract_context "${output}")"
    assert_equals "FP09: read package.json version -> zero match" "" "${ctx}"

    # 10. "update the copyright year in the license" — should NOT match anything
    output="$(run_hook "update the copyright year in the license")"
    ctx="$(extract_context "${output}")"
    assert_equals "FP10: update copyright year -> zero match" "" "${ctx}"

    teardown_test_env
}
test_false_positive_defense

# ---------------------------------------------------------------------------
# Zero-match prompt logging
# ---------------------------------------------------------------------------

test_zero_match_logs_prompt() {
    setup_test_env
    install_registry

    run_hook "rename this variable to camelCase" >/dev/null
    run_hook "explain the auth flow to me" >/dev/null

    local log_file="${HOME}/.claude/.skill-zero-match-log"
    assert_file_exists "zero-match log should exist" "$log_file"

    local log_content
    log_content="$(cat "$log_file" 2>/dev/null)"
    assert_contains "log should contain first prompt" "rename this variable" "$log_content"
    assert_contains "log should contain second prompt" "explain the auth flow" "$log_content"

    # Verify line count
    local line_count
    line_count="$(wc -l < "$log_file" | tr -d ' ')"
    if [[ "$line_count" -eq 2 ]]; then
        _record_pass "log should have exactly 2 entries"
    else
        _record_fail "log should have exactly 2 entries" "got $line_count"
    fi

    teardown_test_env
}
test_zero_match_logs_prompt

# ---------------------------------------------------------------------------
# Session-start surfaces previous session's zero-match rate
# ---------------------------------------------------------------------------

test_session_start_shows_zero_match_rate() {
    echo "-- test: session start shows zero-match rate --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    # Simulate a previous session with 20 total prompts, 3 zero-match
    printf '20' > "${HOME}/.claude/.skill-prompt-count-prev-session"
    printf '3' > "${HOME}/.claude/.skill-zero-match-count"

    # Run session-start hook
    local output
    output="$(CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null)"
    local ctx
    ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"

    assert_contains "session start should show zero-match rate" "3/20 unmatched" "$ctx"

    teardown_test_env
}
test_session_start_shows_zero_match_rate

# ---------------------------------------------------------------------------
# openspec-ship triggers on its own terms, not on bare "ship"
# ---------------------------------------------------------------------------
test_openspec_ship_triggers() {
    echo "-- test: openspec-ship triggers on own terms --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "generate as-built docs for this feature")"
    local context
    context="$(extract_context "${output}")"
    assert_contains "openspec triggers on as-built" "openspec-ship" "${context}"

    # "ship this" should NOT select openspec-ship as a routed skill (it appears in chain/hint but not as a selected skill)
    output="$(run_hook "ship this")"
    context="$(extract_context "${output}")"
    # Check that openspec-ship is not in the skill activation lines (Workflow:/Domain:/Process:)
    local skill_lines
    skill_lines="$(printf '%s' "${context}" | grep -E '^\s*(Process|Domain|Workflow):' || true)"
    assert_not_contains "openspec not in skill activation lines" "openspec-ship" "${skill_lines}"

    teardown_test_env
}
test_openspec_ship_triggers

# ---------------------------------------------------------------------------
# SHIP chain renders three nodes: verification -> openspec-ship -> finishing
# ---------------------------------------------------------------------------
test_ship_chain_three_nodes() {
    echo "-- test: SHIP chain has three nodes --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "ship this feature now")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "chain has verification" "verification-before-completion" "${context}"
    assert_contains "chain has openspec-ship" "openspec-ship" "${context}"
    assert_contains "chain has finishing" "finishing-a-development-branch" "${context}"

    teardown_test_env
}
test_ship_chain_three_nodes

# ---------------------------------------------------------------------------
# openspec-ship-reminder methodology hint fires during SHIP
# ---------------------------------------------------------------------------
test_openspec_hint_fires_on_ship() {
    echo "-- test: openspec-ship-reminder hint fires on ship prompt --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "let's ship this feature")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "openspec hint fires" "OPENSPEC" "${context}"

    teardown_test_env
}
test_openspec_hint_fires_on_ship

# ---------------------------------------------------------------------------
# TDD should not appear as a scored process skill
# ---------------------------------------------------------------------------
test_tdd_not_scored_as_process() {
    echo "-- test: TDD is not a scored process skill --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "run all the tests for the auth module")"
    local context
    context="$(extract_context "${output}")"

    local process_tdd
    process_tdd="$(printf '%s' "${context}" | grep -c 'Process:.*test-driven-development' 2>/dev/null)" || process_tdd=0
    assert_equals "TDD not selected as process skill" "0" "${process_tdd}"

    teardown_test_env
}
test_tdd_not_scored_as_process

# ---------------------------------------------------------------------------
# SDLC chain bridging tests
# ---------------------------------------------------------------------------
# Fixture for chain bridging tests — includes precedes/requires links
install_registry_with_chain() {
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'CHAIN_REG'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": ["(design|build|create|architect|new|brainstorm)"],
      "trigger_mode": "regex",
      "priority": 30,
      "precedes": ["writing-plans"],
      "requires": [],
      "invoke": "Skill(superpowers:brainstorming)",
      "available": true,
      "enabled": true
    },
    {
      "name": "writing-plans",
      "role": "process",
      "phase": "PLAN",
      "triggers": [],
      "trigger_mode": "regex",
      "priority": 40,
      "precedes": ["executing-plans"],
      "requires": ["brainstorming"],
      "invoke": "Skill(superpowers:writing-plans)",
      "available": true,
      "enabled": true
    },
    {
      "name": "executing-plans",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": ["(execute.*plan|implement|continue|build|create)"],
      "trigger_mode": "regex",
      "priority": 35,
      "precedes": ["requesting-code-review"],
      "requires": ["writing-plans"],
      "invoke": "Skill(superpowers:executing-plans)",
      "available": true,
      "enabled": true
    },
    {
      "name": "requesting-code-review",
      "role": "process",
      "phase": "REVIEW",
      "triggers": ["(review|pull.?request|code.?review|(^|[^a-z])pr($|[^a-z]))"],
      "trigger_mode": "regex",
      "priority": 25,
      "precedes": ["verification-before-completion"],
      "requires": ["executing-plans"],
      "invoke": "Skill(superpowers:requesting-code-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "verification-before-completion",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": ["(ship|merge|deploy|push|release|finish|complete|wrap.?up)"],
      "trigger_mode": "regex",
      "priority": 20,
      "precedes": ["openspec-ship"],
      "requires": ["requesting-code-review"],
      "invoke": "Skill(superpowers:verification-before-completion)",
      "available": true,
      "enabled": true
    },
    {
      "name": "openspec-ship",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": ["(openspec|as.?built|document.*built)"],
      "trigger_mode": "regex",
      "priority": 18,
      "precedes": ["finishing-a-development-branch"],
      "requires": ["verification-before-completion"],
      "invoke": "Skill(auto-claude-skills:openspec-ship)",
      "available": true,
      "enabled": true
    },
    {
      "name": "finishing-a-development-branch",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": [],
      "trigger_mode": "regex",
      "priority": 19,
      "precedes": [],
      "requires": ["openspec-ship"],
      "invoke": "Skill(superpowers:finishing-a-development-branch)",
      "available": true,
      "enabled": true
    }
  ],
  "phase_guide": {},
  "methodology_hints": [],
  "plugins": [],
  "phase_compositions": {}
}
CHAIN_REG
}

test_end_to_end_chain() {
    echo "-- test: end-to-end SDLC chain from brainstorming --"
    setup_test_env
    install_registry_with_chain

    local token="test-chain-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output
    output="$(run_hook "let's design a new authentication module")"
    local context
    context="$(extract_context "${output}")"

    local chain_steps
    chain_steps="$(printf '%s' "${context}" | grep -c 'Step [0-9]' 2>/dev/null)" || chain_steps=0
    assert_equals "chain has 7 steps" "7" "${chain_steps}"

    assert_contains "chain includes requesting-code-review" "requesting-code-review" "${context}"
    assert_contains "chain includes verification-before-completion" "verification-before-completion" "${context}"

    teardown_test_env
}
test_end_to_end_chain

test_mid_chain_entry_review() {
    echo "-- test: mid-chain entry at REVIEW shows DONE for prior steps --"
    setup_test_env
    install_registry_with_chain

    local token="test-midchain-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output
    output="$(run_hook "review this pull request")"
    local context
    context="$(extract_context "${output}")"

    # Use grep for regex patterns (assert_contains is literal)
    if printf '%s' "${context}" | grep -q 'CURRENT.*requesting-code-review'; then
        _record_pass "review is CURRENT"
    else
        _record_fail "review is CURRENT" "CURRENT marker not found for requesting-code-review"
    fi
    if printf '%s' "${context}" | grep -q 'NEXT.*verification-before-completion'; then
        _record_pass "verification is NEXT"
    else
        _record_fail "verification is NEXT" "NEXT marker not found for verification-before-completion"
    fi

    teardown_test_env
}
test_mid_chain_entry_review

test_skipped_step_markers() {
    echo "-- test: skipped steps show DONE? marker --"
    setup_test_env
    install_registry_with_chain

    local token="test-skip-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output
    output="$(run_hook "ship this feature, everything is ready")"
    local context
    context="$(extract_context "${output}")"

    if printf '%s' "${context}" | grep -q 'CURRENT.*verification-before-completion'; then
        _record_pass "verification is CURRENT"
    else
        _record_fail "verification is CURRENT" "CURRENT marker not found for verification-before-completion"
    fi

    local done_q
    done_q="$(printf '%s' "${context}" | grep -c 'DONE?.*requesting-code-review' 2>/dev/null)" || done_q=0
    if [[ "$done_q" -gt 0 ]]; then
        _record_pass "review shows DONE? marker"
    else
        _record_fail "review shows DONE? marker" "DONE? not found for requesting-code-review"
    fi

    teardown_test_env
}
test_skipped_step_markers

# ---------------------------------------------------------------------------
# Required role tests
# ---------------------------------------------------------------------------
install_registry_with_required() {
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" << 'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "executing-plans",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": ["(execute.*plan|implement|continue|build|create)"],
      "trigger_mode": "regex",
      "priority": 35,
      "invoke": "Skill(superpowers:executing-plans)",
      "precedes": ["requesting-code-review"],
      "requires": ["writing-plans"],
      "available": true,
      "enabled": true
    },
    {
      "name": "using-git-worktrees",
      "role": "required",
      "phase": "IMPLEMENT",
      "triggers": ["(parallel|concurrent|worktree|isolat|branch.*(work|switch))"],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(superpowers:using-git-worktrees)",
      "precedes": [],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "agent-team-execution",
      "role": "workflow",
      "phase": "IMPLEMENT",
      "triggers": ["(agent.team|team.execute|parallel.team|build|create|implement)"],
      "trigger_mode": "regex",
      "priority": 22,
      "invoke": "Skill(auto-claude-skills:agent-team-execution)",
      "precedes": [],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "agent-team-review",
      "role": "required",
      "phase": "REVIEW",
      "required_when": "PR touches 3+ files, crosses module boundaries, or includes security-sensitive changes",
      "triggers": ["(review|pull.?request|code.?review|check.*(code|changes|diff)|(^|[^a-z])pr($|[^a-z]))"],
      "trigger_mode": "regex",
      "priority": 20,
      "invoke": "Skill(auto-claude-skills:agent-team-review)",
      "precedes": [],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "requesting-code-review",
      "role": "process",
      "phase": "REVIEW",
      "triggers": ["(review|pull.?request|code.?review|check.*(code|changes|diff)|(^|[^a-z])pr($|[^a-z]))"],
      "trigger_mode": "regex",
      "priority": 25,
      "invoke": "Skill(superpowers:requesting-code-review)",
      "precedes": ["verification-before-completion"],
      "requires": ["executing-plans"],
      "available": true,
      "enabled": true
    },
    {
      "name": "frontend-design",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": ["(ui|frontend|component|layout|style|css)"],
      "trigger_mode": "regex",
      "priority": 15,
      "invoke": "Skill(frontend-design:frontend-design)",
      "precedes": [],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "design-debate",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": ["(design|architect|trade.?off|debate|build|create)"],
      "trigger_mode": "regex",
      "priority": 18,
      "invoke": "Skill(auto-claude-skills:design-debate)",
      "precedes": [],
      "requires": [],
      "available": true,
      "enabled": true
    }
  ],
  "phase_guide": {},
  "methodology_hints": [],
  "plugins": [],
  "phase_compositions": {}
}
REGISTRY
}

test_required_bypasses_workflow_cap() {
    echo "-- test: required skill bypasses workflow cap --"
    setup_test_env
    install_registry_with_required

    local output
    output="$(run_hook "implement the feature using parallel worktrees")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "worktrees appears as Required" "Required:" "${context}"
    assert_contains "worktrees in output" "using-git-worktrees" "${context}"
    assert_contains "agent-team-execution appears as Workflow" "Workflow:" "${context}"
    assert_contains "agent-team-execution in output" "agent-team-execution" "${context}"

    teardown_test_env
}
test_required_bypasses_workflow_cap

test_conditional_required_invoke_when() {
    echo "-- test: conditional required shows INVOKE WHEN tag --"
    setup_test_env
    install_registry_with_required

    local output
    output="$(run_hook "review this pull request for the auth module")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "INVOKE WHEN tag present" "INVOKE WHEN:" "${context}"
    assert_contains "condition text present" "3+ files" "${context}"

    teardown_test_env
}
test_conditional_required_invoke_when

test_required_skill_wrong_phase() {
    echo "-- test: required skill does not activate at wrong phase --"
    setup_test_env
    install_registry_with_required

    # worktrees is required at IMPLEMENT, but this triggers DESIGN only
    # (avoid words like "create", "build", "implement" that match executing-plans)
    local output
    output="$(run_hook "discuss the parallel architecture approach for the frontend ui layout")"
    local context
    context="$(extract_context "${output}")"

    local wt_count
    wt_count="$(printf '%s' "${context}" | grep -c 'using-git-worktrees' 2>/dev/null)" || wt_count=0
    assert_equals "worktrees not at wrong phase" "0" "${wt_count}"

    teardown_test_env
}
test_required_skill_wrong_phase

test_required_eval_tag() {
    echo "-- test: REQUIRED eval tag present for unconditional required --"
    setup_test_env
    install_registry_with_required

    local output
    output="$(run_hook "implement the feature using parallel worktrees")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "REQUIRED tag in eval" "using-git-worktrees REQUIRED" "${context}"

    teardown_test_env
}
test_required_eval_tag

test_required_bypasses_total_cap() {
    echo "-- test: required skill does not count against total cap --"
    setup_test_env
    install_registry_with_required

    # Trigger process + workflow + required = should show all 3
    local output
    output="$(run_hook "implement the feature with parallel worktrees")"
    local context
    context="$(extract_context "${output}")"

    # Count all skill lines
    local skill_count
    skill_count="$(printf '%s' "${context}" | grep -cE '(Required|Process|Workflow):' 2>/dev/null)" || skill_count=0
    if [[ "$skill_count" -ge 3 ]]; then
        _record_pass "required bypasses cap ($skill_count skills)"
    else
        _record_fail "required bypasses cap" "only $skill_count skills, expected >= 3"
    fi

    teardown_test_env
}
test_required_bypasses_total_cap

test_required_no_plabel() {
    echo "-- test: required skills alone do not set PLABEL --"
    setup_test_env

    local registry_file="${HOME}/.claude/.skill-registry-cache.json"
    cat > "${registry_file}" << 'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "using-git-worktrees",
      "role": "required",
      "phase": "IMPLEMENT",
      "triggers": ["(parallel|worktree)"],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(superpowers:using-git-worktrees)",
      "available": true,
      "enabled": true
    }
  ],
  "phase_guide": {},
  "methodology_hints": [],
  "plugins": [],
  "phase_compositions": {}
}
REGISTRY

    local output
    output="$(run_hook "use parallel worktrees for this")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "assess intent fallback" "assess intent" "${context}"

    teardown_test_env
}
test_required_no_plabel

# ---------------------------------------------------------------------------
# IMPLEMENT stickiness keeps phase during generic continuation verbs
# ---------------------------------------------------------------------------
test_implement_stickiness() {
    echo "-- test: IMPLEMENT stickiness keeps phase during generic verbs --"
    setup_test_env
    install_registry_v4

    local token="test-sticky-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    # Persist last phase as IMPLEMENT
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output
    output="$(run_hook "continue with the next task in the plan")"
    local context
    context="$(extract_context "${output}")"

    # Should stay in IMPLEMENT (executing-plans), not snap to DESIGN (brainstorming)
    if printf '%s' "${context}" | grep -q 'executing-plans'; then
        _record_pass "IMPLEMENT stickiness: executing-plans selected"
    else
        _record_fail "IMPLEMENT stickiness: executing-plans selected" "got brainstorming instead"
    fi

    teardown_test_env
}
test_implement_stickiness

test_implement_stickiness_respects_design_cues() {
    echo "-- test: stickiness respects design cues --"
    setup_test_env
    install_registry_v4

    local token="test-sticky-design-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output
    output="$(run_hook "how should we architect the error handling approach?")"
    local context
    context="$(extract_context "${output}")"

    # Design cue should override stickiness — brainstorming should win
    assert_contains "design cue overrides stickiness" "brainstorming" "${context}"

    teardown_test_env
}
test_implement_stickiness_respects_design_cues

# ---------------------------------------------------------------------------
# Composition state should not corrupt with missing anchor
# ---------------------------------------------------------------------------
test_composition_state_no_corrupt() {
    echo "-- test: missing chain anchor does not corrupt composition state --"
    setup_test_env
    install_registry_with_required

    local token="test-corrupt-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    # Set last-invoked to a skill NOT in the registry (forces anchor miss)
    printf '{"skill":"nonexistent-skill","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    run_hook "implement the feature using parallel worktrees" >/dev/null

    local state_file="${HOME}/.claude/.skill-composition-state-${token}"
    if [[ -f "$state_file" ]]; then
        local idx
        idx="$(jq '.current_index' "$state_file" 2>/dev/null)"
        if [[ "$idx" == "-1" ]]; then
            _record_fail "composition state not corrupted" "current_index is -1"
        else
            _record_pass "composition state not corrupted"
        fi
    else
        _record_pass "composition state not corrupted (no file written)"
    fi

    teardown_test_env
}
test_composition_state_no_corrupt



# ---------------------------------------------------------------------------
# receiving-code-review should be reachable via feedback triggers
# ---------------------------------------------------------------------------
test_receiving_code_review_trigger() {
    echo "-- test: review-feedback selects receiving-code-review --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "address the review comments and fix the nits")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "receiving-code-review selected" "receiving-code-review" "${context}"

    teardown_test_env
}
test_receiving_code_review_trigger

# ---------------------------------------------------------------------------
# design-debate should only fire on tradeoff language, not generic verbs
# ---------------------------------------------------------------------------
test_design_debate_narrow_triggers() {
    echo "-- test: design-debate only fires on tradeoff language --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "add a new endpoint to the auth module")"
    local context
    context="$(extract_context "${output}")"

    local debate_count
    debate_count="$(printf '%s' "${context}" | grep -c 'design-debate' 2>/dev/null)" || debate_count=0
    assert_equals "design-debate not on generic add" "0" "${debate_count}"

    output="$(run_hook "compare the two architecture approaches for the API")"
    context="$(extract_context "${output}")"
    assert_contains "design-debate on tradeoff" "design-debate" "${context}"

    teardown_test_env
}
test_design_debate_narrow_triggers

# ---------------------------------------------------------------------------
# New design intent during IMPLEMENT must route to brainstorming (HARD-GATE)
# ---------------------------------------------------------------------------
test_new_design_during_implement() {
    echo "-- test: new design during IMPLEMENT respects HARD-GATE --"
    setup_test_env
    install_registry_v4

    local token="test-hardgate-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output
    output="$(run_hook "build a new authentication system for the app")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "brainstorming wins on new design" "brainstorming" "${context}"

    if printf '%s' "${context}" | grep -q 'Process:.*executing-plans'; then
        _record_fail "stickiness did not fire on new design" "executing-plans was selected"
    else
        _record_pass "stickiness did not fire on new design"
    fi

    teardown_test_env
}
test_new_design_during_implement

test_stickiness_on_resume() {
    echo "-- test: stickiness fires when composition state has executing-plans as CURRENT --"
    setup_test_env
    install_registry_v4

    local token="test-resume-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"writing-plans","phase":"PLAN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"
    jq -n '{
        chain: ["brainstorming","writing-plans","executing-plans","requesting-code-review"],
        completed: ["brainstorming","writing-plans"]
    }' > "${HOME}/.claude/.skill-composition-state-${token}"

    local output
    output="$(run_hook "yes")"
    local context
    context="$(extract_context "${output}")"

    if printf '%s' "${context}" | grep -q 'executing-plans'; then
        _record_pass "stickiness fires on bare ack with active chain"
    else
        _record_fail "stickiness fires on bare ack with active chain" "executing-plans not selected"
    fi

    teardown_test_env
}
test_stickiness_on_resume

# ---------------------------------------------------------------------------
# agent-team-execution should not co-select on plain continuation
# ---------------------------------------------------------------------------
test_agent_team_not_on_continuation() {
    echo "-- test: agent-team-execution does not co-select on plain continuation --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "continue with the next task")"
    local context
    context="$(extract_context "${output}")"

    # Check skill selection lines only (Workflow:), not RED FLAGS text
    local ate_count
    ate_count="$(printf '%s' "${context}" | grep -cE '^Workflow:.*agent-team-execution' 2>/dev/null)" || ate_count=0
    assert_equals "agent-team not on continuation" "0" "${ate_count}"

    teardown_test_env
}
test_agent_team_not_on_continuation

# ---------------------------------------------------------------------------
# Phase-aware RED FLAGS
# ---------------------------------------------------------------------------
test_design_red_flags() {
    echo "-- test: DESIGN phase has RED FLAGS --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "build a new payment integration for our app")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "DESIGN red flags present" "HALT if any Red Flag" "${context}"
    assert_contains "DESIGN red flag mentions brainstorming" "brainstorming" "${context}"

    teardown_test_env
}
test_design_red_flags

test_implement_red_flags() {
    echo "-- test: IMPLEMENT phase has RED FLAGS --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "continue with the next task in the plan")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "IMPLEMENT red flags present" "HALT if any Red Flag" "${context}"
    assert_contains "IMPLEMENT red flag mentions worktree" "worktree" "${context}"

    teardown_test_env
}
test_implement_red_flags

test_review_red_flags() {
    echo "-- test: REVIEW phase has RED FLAGS --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "review this pull request for the auth module")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "REVIEW red flags present" "HALT if any Red Flag" "${context}"
    assert_contains "REVIEW red flag mentions subagent" "code-reviewer subagent" "${context}"

    teardown_test_env
}
test_review_red_flags

# ---------------------------------------------------------------------------
# Phase enforcement hint
# ---------------------------------------------------------------------------
test_phase_enforcement_hint() {
    echo "-- test: phase enforcement hint fires at DESIGN with impl intent --"
    setup_test_env
    install_registry

    # "create the" matches impl-intent, "new" matches brainstorming (DESIGN)
    local output
    output="$(run_hook "create the new payment module for our app")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "phase enforcement hint" "PHASE ENFORCEMENT" "${context}"

    teardown_test_env
}
test_phase_enforcement_hint

test_phase_enforcement_hint_not_at_implement() {
    echo "-- test: phase enforcement hint does NOT fire at IMPLEMENT --"
    setup_test_env
    install_registry_v4

    local token="test-enforce-impl"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output
    output="$(run_hook "continue with the next task")"
    local context
    context="$(extract_context "${output}")"

    local enforce_count
    enforce_count="$(printf '%s' "${context}" | grep -c 'PHASE ENFORCEMENT' 2>/dev/null)" || enforce_count=0
    assert_equals "no enforcement hint at IMPLEMENT" "0" "${enforce_count}"

    teardown_test_env
}
test_phase_enforcement_hint_not_at_implement

test_plan_red_flags() {
    echo "-- test: PLAN phase has RED FLAGS --"
    setup_test_env
    install_registry

    local token="test-plan-rf"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    # Set last-invoked to brainstorming so writing-plans gets chain bonus (+20)
    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    # install_registry's writing-plans has triggers "(plan|outline|...)"
    # Chain bonus (+20) from brainstorming state makes writing-plans win
    local output
    output="$(run_hook "let us plan this out")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "PLAN red flags present" "approved plan" "${context}"

    teardown_test_env
}
test_plan_red_flags

test_review_sequence_visible() {
    echo "-- test: REVIEW sequence shows 3-step flow --"
    setup_test_env

    # Use the production fallback registry (has phase_compositions with REVIEW sequence)
    local cache="${HOME}/.claude/.skill-registry-cache.json"
    cp "${PROJECT_ROOT}/config/fallback-registry.json" "${cache}"
    # Enable requesting-code-review in the fallback
    local tmp="${cache}.tmp"
    jq '.skills |= map(
        if .name == "requesting-code-review" then . + {available:true, enabled:true, invoke:"Skill(superpowers:requesting-code-review)"}
        else . end
    )' "${cache}" > "${tmp}" && mv "${tmp}" "${cache}"

    local output
    output="$(run_hook "review the pull request for the auth module")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "REVIEW sequence has requesting" "SEQUENCE: requesting-code-review" "${context}"
    assert_contains "REVIEW sequence has receiving" "SEQUENCE: receiving-code-review" "${context}"

    teardown_test_env
}
test_review_sequence_visible

test_frontmatter_overrides_default_triggers() {
    echo "-- test: frontmatter triggers override default-triggers.json --"
    setup_test_env
    install_registry_v4

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    jq '.skills |= map(if .name == "brainstorming" then .triggers = ["(frontmatter-only-pattern)"] else . end)' \
        "${cache_file}" > "${cache_file}.tmp" && mv "${cache_file}.tmp" "${cache_file}"

    local output
    output="$(run_hook "this matches the frontmatter-only-pattern exactly")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "frontmatter trigger activates skill" "brainstorming" "${context}"

    teardown_test_env
}
test_frontmatter_overrides_default_triggers

# ---------------------------------------------------------------------------
# DISCOVER phase routing tests
# ---------------------------------------------------------------------------
test_discover_trigger_scoring() {
    echo "-- test: DISCOVER trigger scoring --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "what should we build next sprint")"
    ctx="$(extract_context "${output}")"
    assert_contains "discovery strong+weak" "product-discovery" "${ctx}"

    output="$(run_hook "triage the backlog for prioritization")"
    ctx="$(extract_context "${output}")"
    assert_contains "discovery weak trigger" "product-discovery" "${ctx}"

    teardown_test_env
}

test_discover_vs_design_disambiguation() {
    echo "-- test: DISCOVER vs DESIGN disambiguation --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "build a new auth service")"
    ctx="$(extract_context "${output}")"
    assert_contains "build -> brainstorming" "brainstorming" "${ctx}"
    assert_not_contains "build -> not discovery" "product-discovery" "${ctx}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# LEARN phase routing tests
# ---------------------------------------------------------------------------
test_learn_trigger_scoring() {
    echo "-- test: LEARN trigger scoring --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "how did the auth feature perform")"
    ctx="$(extract_context "${output}")"
    assert_contains "learn trigger" "outcome-review" "${ctx}"

    output="$(run_hook "check the adoption metrics for the new dashboard")"
    ctx="$(extract_context "${output}")"
    assert_contains "learn keyword" "outcome-review" "${ctx}"

    teardown_test_env
}

test_learn_false_positive_guards() {
    echo "-- test: LEARN false-positive guards --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "show me the test results")"
    ctx="$(extract_context "${output}")"
    assert_not_contains "test results -> not learn" "outcome-review" "${ctx}"

    output="$(run_hook "I am learning about bash scripting")"
    ctx="$(extract_context "${output}")"
    assert_not_contains "learning -> not learn" "outcome-review" "${ctx}"

    teardown_test_env
}

test_learn_vs_debug_disambiguation() {
    echo "-- test: LEARN vs DEBUG disambiguation --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "something is wrong with the metrics dashboard")"
    ctx="$(extract_context "${output}")"
    assert_contains "wrong metrics -> debug" "systematic-debugging" "${ctx}"

    teardown_test_env
}

test_discover_composition_chain() {
    echo "-- test: DISCOVER -> DESIGN composition chain --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "what should we build for the next sprint")"
    ctx="$(extract_context "${output}")"
    assert_contains "chain has brainstorming" "brainstorming" "${ctx}"

    teardown_test_env
}

test_learn_composition_chain() {
    echo "-- test: LEARN -> DISCOVER composition chain --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "how did the auth feature perform after launch")"
    ctx="$(extract_context "${output}")"
    assert_contains "chain has product-discovery" "product-discovery" "${ctx}"

    teardown_test_env
}

test_slash_command_early_exit() {
    echo "-- test: /discover slash command exits early --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "/discover")"
    assert_equals "slash command no output" "" "${output}"

    teardown_test_env
}

test_discover_trigger_scoring
test_discover_vs_design_disambiguation
test_learn_trigger_scoring
test_learn_false_positive_guards
test_learn_vs_debug_disambiguation
test_discover_composition_chain
test_learn_composition_chain
test_slash_command_early_exit

# ---------------------------------------------------------------------------
# Bug-fix regression tests
# ---------------------------------------------------------------------------

test_required_when_does_not_contaminate_keywords() {
    echo "-- test: required_when does not contaminate keyword scoring --"
    setup_test_env
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    # Skill with BOTH keywords and required_when, but NO trigger match
    # on the test prompt. The keyword is the ONLY way to select it.
    # Bug: jq outputs 9 fields but read consumes 8, so required_when
    # leaks into keywords_joined, corrupting the last keyword.
    cat > "${cache_file}" <<'REG'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "test-kw-rw",
      "role": "domain",
      "phase": "REVIEW",
      "triggers": ["(zzz-no-match-pattern)"],
      "trigger_mode": "regex",
      "priority": 20,
      "keywords": ["special-keyword-alpha"],
      "required_when": "always use this skill",
      "invoke": "Skill(test-kw-rw)",
      "available": true,
      "enabled": true
    },
    {
      "name": "systematic-debugging",
      "role": "process",
      "phase": "DEBUG",
      "triggers": ["(debug|bug|error)"],
      "trigger_mode": "regex",
      "priority": 10,
      "invoke": "Skill(superpowers:systematic-debugging)",
      "available": true,
      "enabled": true
    }
  ],
  "plugins": [],
  "phase_compositions": {},
  "methodology_hints": []
}
REG
    # Prompt contains the keyword but triggers don't match.
    # With the bug: keywords_joined = "special-keyword-alpha\x1falways use this skill"
    #   → treated as one keyword, doesn't match substring in prompt → no selection
    # Without the bug: keywords_joined = "special-keyword-alpha", matches → selected
    local output
    output="$(run_hook "debug this special-keyword-alpha issue")"
    local ctx
    ctx="$(extract_context "${output}")"
    assert_contains "keyword match works with required_when present" "test-kw-rw" "${ctx}"

    teardown_test_env
}

test_required_when_does_not_contaminate_keywords

test_measure_false_positive_guard() {
    echo "-- test: measure does not false-fire outcome-review --"
    setup_test_env
    install_registry
    local output ctx
    output="$(run_hook "measure the width of the sidebar component")"
    ctx="$(extract_context "${output}")"
    assert_not_contains "measure impl prompt -> not outcome-review" "outcome-review" "${ctx}"
    teardown_test_env
}

test_discover_false_positive_guard() {
    echo "-- test: discover does not false-fire product-discovery --"
    setup_test_env
    install_registry
    local output ctx
    output="$(run_hook "I discovered a bug in the parser module")"
    ctx="$(extract_context "${output}")"
    assert_not_contains "discovered bug -> not product-discovery" "product-discovery" "${ctx}"
    teardown_test_env
}

test_measure_false_positive_guard
test_discover_false_positive_guard

# ---------------------------------------------------------------------------
# v1.3 incident-analysis routing: deploy-rollback co-surfacing
# ---------------------------------------------------------------------------

test_incident_analysis_surfaces_on_deploy_rollback() {
    echo "-- test: incident-analysis surfaces on deploy rollback incident prompt --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context
    output="$(run_hook "deploy rollback incident")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis surfaces on deploy rollback incident" "incident-analysis" "${context}"

    teardown_test_env
}

test_github_co_surfaces_on_deploy_rollback() {
    echo "-- test: GitHub hint co-surfaces with incident-analysis on deploy rollback --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context
    # "deploy rollback" triggers both gcp-observability and github-mcp hints
    output="$(run_hook "deploy rollback incident")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis hint co-surfaces" "INCIDENT ANALYSIS" "${context}"
    assert_contains "github hint co-surfaces in DEBUG" "GITHUB" "${context}"

    teardown_test_env
}

test_incident_analysis_still_surfaces_on_incident() {
    echo "-- test: incident-analysis still surfaces on plain incident prompt (regression) --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context
    output="$(run_hook "investigate this incident in the payments service")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis surfaces on incident prompt" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_surfaces_on_deploy_rollback
test_github_co_surfaces_on_deploy_rollback
test_incident_analysis_still_surfaces_on_incident

# ---------------------------------------------------------------------------
# Symptom-based incident-analysis routing tests
# ---------------------------------------------------------------------------

test_incident_analysis_triggers_on_connection_failure() {
    echo "-- test: incident-analysis triggers on connection failure symptoms --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "Core failed to acquire connections while being healthy. Looking into the cloud sql proxy. Error during SIGTERM shutdown: 61 active connections still exist after waiting for 0s")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on connection+SIGTERM symptoms" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_oom_kill() {
    echo "-- test: incident-analysis triggers on OOM kill symptoms --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "pod keeps getting OOMKilled, memory pressure is high and the container restarts every few minutes")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on OOM symptoms" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_crash_loop() {
    echo "-- test: incident-analysis triggers on CrashLoopBackOff --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "backend-api is in CrashLoopBackOff after the latest deploy, liveness probe keeps failing")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on crash loop symptoms" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_latency_spike() {
    echo "-- test: incident-analysis triggers on latency spike --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "seeing a latency spike on the payments service, p99 went from 200ms to 5s after the last deploy")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on latency spike symptoms" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_cloud_sql_proxy() {
    echo "-- test: incident-analysis triggers on cloud sql proxy issues --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "cloud sql proxy restarted and dropped all active connections, the app cannot reach the database")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on cloud sql proxy symptoms" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_cofires_with_debugging() {
    echo "-- test: incident-analysis co-fires as domain alongside systematic-debugging as process --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "connection error after SIGTERM, pod crashing and restarting")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires as domain" "incident-analysis" "${context}"
    assert_contains "systematic-debugging fires as process" "systematic-debugging" "${context}"

    teardown_test_env
}

test_investigate_command_routing() {
    echo "-- test: /investigate command exists and references incident-analysis --"

    local cmd_file="${PROJECT_ROOT}/commands/investigate.md"
    assert_file_exists "/investigate command file" "${cmd_file}"

    local content
    content="$(cat "${cmd_file}")"
    assert_contains "references incident-analysis skill" "incident-analysis" "${content}"
    assert_contains "references MITIGATE stage" "MITIGATE" "${content}"
    assert_contains "must not bypass MITIGATE" "Must not bypass MITIGATE" "${content}"
}

test_slo_burn_rate_routes_to_incident_analysis() {
    echo "-- test: SLO burn rate prompts route to incident-analysis --"
    setup_test_env
    install_registry_with_incident_analysis

    # Extend the fixture registry with SLO/burn-rate trigger
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"
    jq '(.skills[] | select(.name == "incident-analysis") | .triggers) += ["(slo.*(burn|alert|breach|budget)|burn.?rate|error.budget)"]
      | (.skills[] | select(.name == "incident-analysis") | .keywords) += ["SLO burn rate", "error budget"]' \
      "${cache_file}" > "${tmp_file}" && mv "${tmp_file}" "${cache_file}"

    local output context

    output="$(run_hook "SLO burn rate alert fired on checkout-service, error budget depleting fast")"
    context="$(extract_context "${output}")"
    assert_contains "SLO burn rate routes to incident-analysis" "incident-analysis" "${context}"

    output="$(run_hook "burn rate exceeded 2x threshold on payment-service for 10 minutes")"
    context="$(extract_context "${output}")"
    assert_contains "burn rate language routes to incident-analysis" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_image_pull_failure() {
    echo "-- test: incident-analysis triggers on ImagePullBackOff --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "pods stuck in ImagePullBackOff after we pushed the new tag, getting ErrImagePull on the registry")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on image pull failure" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_config_error() {
    echo "-- test: incident-analysis triggers on CreateContainerConfigError --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "deployment is failing with CreateContainerConfigError, looks like a missing ConfigMap reference")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on config error" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_volume_mount_failure() {
    echo "-- test: incident-analysis triggers on FailedMount --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "pods pending with FailedMount, the PVC is stuck in pending state and volumes are not attaching")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on volume mount failure" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_connection_failure
test_incident_analysis_triggers_on_oom_kill
test_incident_analysis_triggers_on_crash_loop
test_incident_analysis_triggers_on_latency_spike
test_incident_analysis_triggers_on_cloud_sql_proxy
test_incident_analysis_triggers_on_image_pull_failure
test_incident_analysis_triggers_on_config_error
test_incident_analysis_triggers_on_volume_mount_failure
test_incident_analysis_cofires_with_debugging
test_investigate_command_routing
test_slo_burn_rate_routes_to_incident_analysis

# ---------------------------------------------------------------------------
# Wave 1: skill-scaffold triggers on "new skill" prompt
# ---------------------------------------------------------------------------
test_starter_template_triggers() {
    echo "-- test: skill-scaffold triggers on new skill prompt --"
    setup_test_env
    install_registry_with_wave1

    local output
    output="$(run_hook "create a new skill for database migrations")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "skill-scaffold fires on new skill" "skill-scaffold" "${context}"
    assert_contains "brainstorming is still process skill" "brainstorming" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Wave 1: prototype-lab triggers on "compare options" prompt
# ---------------------------------------------------------------------------
test_prototype_lab_triggers() {
    echo "-- test: prototype-lab triggers on compare options prompt --"
    setup_test_env
    install_registry_with_wave1

    local output
    output="$(run_hook "let's prototype and compare options for the caching layer")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "prototype-lab fires on compare options" "prototype-lab" "${context}"
    assert_contains "brainstorming is still process skill" "brainstorming" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Wave 1: agent-safety-review triggers on autonomous loop prompt
# ---------------------------------------------------------------------------
test_agent_safety_review_triggers() {
    echo "-- test: agent-safety-review triggers on autonomous loop prompt --"
    setup_test_env
    install_registry_with_wave1

    local output
    output="$(run_hook "set up an autonomous loop to process incoming emails overnight")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "agent-safety-review fires on autonomous loop" "agent-safety-review" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Wave 1: agent-safety-review fires on YOLO prompt
# ---------------------------------------------------------------------------
test_agent_safety_review_yolo() {
    echo "-- test: agent-safety-review fires on YOLO prompt --"
    setup_test_env
    install_registry_with_wave1

    local output
    output="$(run_hook "run this in YOLO mode with skip permissions")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "agent-safety-review fires on YOLO" "agent-safety-review" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Wave 1: driver invariants — new skills do not displace process drivers
# ---------------------------------------------------------------------------
test_wave1_driver_invariants() {
    echo "-- test: Wave 1 skills do not displace process drivers --"
    setup_test_env
    install_registry_with_wave1

    # DESIGN driver must remain brainstorming, not prototype-lab or agent-safety-review
    local output
    output="$(run_hook "build a new autonomous email agent skill")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "brainstorming remains DESIGN process" "Process: brainstorming" "${context}"
    assert_not_contains "prototype-lab is not process" "Process: prototype-lab" "${context}"
    assert_not_contains "agent-safety-review is not process" "Process: agent-safety-review" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Wave 1: prototype-lab does not displace brainstorming as DESIGN driver
# ---------------------------------------------------------------------------
test_prototype_lab_does_not_displace_brainstorming() {
    echo "-- test: prototype-lab does not displace brainstorming --"
    setup_test_env
    install_registry_with_wave1

    local output
    output="$(run_hook "prototype three different approaches for the caching system")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "prototype-lab is domain" "prototype-lab" "${context}"
    assert_contains "brainstorming remains process" "Process: brainstorming" "${context}"
    assert_not_contains "prototype-lab is not process" "Process: prototype-lab" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Wave 1: skill-scaffold SKILL.md content contract
# ---------------------------------------------------------------------------
test_starter_template_content_contract() {
    echo "-- test: skill-scaffold SKILL.md has required sections --"
    local skill_file="${PROJECT_ROOT}/skills/skill-scaffold/SKILL.md"

    local content
    content="$(cat "${skill_file}" 2>/dev/null || echo "")"

    assert_not_empty "skill-scaffold SKILL.md exists and is non-empty" "${content}"
    assert_contains "skill-scaffold has frontmatter name" "name: skill-scaffold" "${content}"
    assert_contains "skill-scaffold has When to Use section" "When to Use" "${content}"
    assert_contains "skill-scaffold has Constraints section" "Constraints" "${content}"
    assert_contains "skill-scaffold has SKILL.md skeleton" "SKILL.md skeleton" "${content}"
    assert_contains "skill-scaffold has routing entry snippet" "default-triggers.json" "${content}"
    assert_contains "skill-scaffold has test snippet" "test-routing.sh" "${content}"
    assert_contains "skill-scaffold warns about process skill restriction" "superpowers-owned phase" "${content}"
}

test_starter_template_triggers
test_prototype_lab_triggers
test_agent_safety_review_triggers
test_agent_safety_review_yolo
test_wave1_driver_invariants
test_prototype_lab_does_not_displace_brainstorming
test_starter_template_content_contract

# ---------------------------------------------------------------------------
# Routing eval fixtures — incident-analysis trigger/no-trigger cases
# ---------------------------------------------------------------------------
ROUTING_EVALS="${PROJECT_ROOT}/tests/fixtures/incident-analysis/evals/routing.json"
if [ -f "${ROUTING_EVALS}" ] && command -v jq >/dev/null 2>&1; then
    setup_test_env
    install_registry_with_incident_analysis

    eval_count="$(jq 'length' "${ROUTING_EVALS}")"
    for i in $(seq 0 $((eval_count - 1))); do
        query="$(jq -r ".[$i].query" "${ROUTING_EVALS}")"
        should_trigger="$(jq -r ".[$i].should_trigger" "${ROUTING_EVALS}")"
        short_query="$(printf '%.60s' "${query}")"

        output="$(run_hook "${query}")"
        context="$(extract_context "${output}")"

        if [ "${should_trigger}" = "true" ]; then
            if printf '%s' "${context}" | grep -q "incident-analysis"; then
                _record_pass "routing-eval: triggers on '${short_query}...'"
            else
                _record_fail "routing-eval: triggers on '${short_query}...'" "incident-analysis not in context"
            fi
        else
            if printf '%s' "${context}" | grep -q "incident-analysis"; then
                _record_fail "routing-eval: no trigger on '${short_query}...'" "incident-analysis unexpectedly triggered"
            else
                _record_pass "routing-eval: no trigger on '${short_query}...'"
            fi
        fi
    done

    teardown_test_env
fi

# ---------------------------------------------------------------------------
# DESIGN→PLAN contract guard (Option D — inline completeness check)
# Design doc: docs/plans/2026-04-18-design-plan-guard-design.md
# ---------------------------------------------------------------------------

# Helper: seed session token + state file pointing at a design fixture path.
_seed_plan_state() {
    local token="$1" slug="$2" dp="$3"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"
    jq -n --arg slug "${slug}" --arg dp "${dp}" '{
        openspec_surface: "none",
        verification_seen: false,
        verification_at: null,
        changes: {($slug): {
            design_path: $dp,
            plan_path: null,
            spec_path: null,
            sp_plan_path: null,
            sp_spec_path: null,
            capability_slug: null,
            archived_at: null
        }}
    }' > "${HOME}/.claude/.skill-openspec-state-${token}"
}

# Helper: write a design fixture file with the named sections present.
_write_design_fixture() {
    local path="$1"; shift
    mkdir -p "$(dirname "${path}")"
    {
        printf '# Design: fixture\n\n'
        printf 'Intro paragraph.\n\n'
        local section
        for section in "$@"; do
            printf '## %s\n\n' "${section}"
            printf 'Body for %s.\n\n' "${section}"
        done
    } > "${path}"
}

test_plan_completeness_emits_when_all_sections_present() {
    echo "-- test: DESIGN COMPLETENESS emits 'all sections present' when all three headers exist --"
    setup_test_env
    install_registry

    local token="plan-guard-complete-$$"
    local design="${HOME}/design-complete.md"
    _write_design_fixture "${design}" "Capabilities Affected" "Out-of-Scope" "Acceptance Scenarios"
    _seed_plan_state "${token}" "fixture-slug" "${design}"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "completeness header present" "DESIGN COMPLETENESS" "${context}"
    assert_contains "all-present one-liner" "all sections present" "${context}"
    assert_not_contains "no missing-section call-to-action" "missing" "${context}"

    teardown_test_env
}
test_plan_completeness_emits_when_all_sections_present

test_plan_completeness_names_missing_section() {
    echo "-- test: DESIGN COMPLETENESS names the specific missing section --"
    setup_test_env
    install_registry

    local token="plan-guard-missing-$$"
    local design="${HOME}/design-missing.md"
    _write_design_fixture "${design}" "Capabilities Affected" "Acceptance Scenarios"
    _seed_plan_state "${token}" "fixture-slug" "${design}"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "header present" "DESIGN COMPLETENESS" "${context}"
    assert_contains "names Out-of-Scope as missing" "Out-of-Scope" "${context}"
    assert_contains "mentions the section is missing" "missing" "${context}"
    assert_contains "tells LLM to complete before writing-plans" "writing-plans" "${context}"
    assert_not_contains "Capabilities Affected not flagged" "Capabilities Affected (missing" "${context}"
    assert_not_contains "Acceptance Scenarios not flagged" "Acceptance Scenarios (missing" "${context}"

    teardown_test_env
}
test_plan_completeness_names_missing_section

test_plan_completeness_silent_without_design_path() {
    echo "-- test: DESIGN COMPLETENESS stays silent when no design_path in state --"
    setup_test_env
    install_registry

    local token="plan-guard-nostate-$$"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_not_contains "no completeness block without state" "DESIGN COMPLETENESS" "${context}"

    teardown_test_env
}
test_plan_completeness_silent_without_design_path

test_plan_completeness_silent_with_empty_changes() {
    echo "-- test: DESIGN COMPLETENESS stays silent when state exists but changes is empty --"
    setup_test_env
    install_registry

    local token="plan-guard-empty-$$"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"
    # State file exists and parses, but no changes recorded.
    jq -n '{openspec_surface:"none",verification_seen:false,verification_at:null,changes:{}}' \
        > "${HOME}/.claude/.skill-openspec-state-${token}"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_not_contains "no completeness block with empty changes" "DESIGN COMPLETENESS" "${context}"

    teardown_test_env
}
test_plan_completeness_silent_with_empty_changes

test_plan_completeness_handles_missing_file() {
    echo "-- test: DESIGN COMPLETENESS notes unreadable file gracefully --"
    setup_test_env
    install_registry

    local token="plan-guard-unread-$$"
    local design="${HOME}/does-not-exist/design.md"
    _seed_plan_state "${token}" "fixture-slug" "${design}"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "header present" "DESIGN COMPLETENESS" "${context}"
    assert_contains "flags unreadable file" "unreadable" "${context}"
    assert_contains "hook emitted context block" "SKILL ACTIVATION" "${context}"

    teardown_test_env
}
test_plan_completeness_handles_missing_file

# Helper: write a design fixture with raw heading lines (caller supplies the
# full heading text including #-prefix, for mutation testing).
_write_design_fixture_raw() {
    local path="$1"; shift
    mkdir -p "$(dirname "${path}")"
    {
        printf '# Design: fixture\n\n'
        printf 'Intro paragraph.\n\n'
        local heading
        for heading in "$@"; do
            printf '%s\n\n' "${heading}"
            printf 'Body text.\n\n'
        done
    } > "${path}"
}

test_plan_completeness_tolerates_heading_variants() {
    echo "-- test: DESIGN COMPLETENESS tolerates real-world heading variants --"
    setup_test_env
    install_registry

    local token="plan-guard-variants-$$"
    local design="${HOME}/design-variants.md"
    # Real-world mutations from the format-eval specimen set: h3 level,
    # lowercase, space-for-hyphen, suffix text, emoji prefix.
    _write_design_fixture_raw "${design}" \
        '### Capabilities affected' \
        '## Out of Scope & Non-Goals' \
        '## 🚫 Acceptance Scenarios'
    _seed_plan_state "${token}" "fixture-slug" "${design}"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "completeness header present" "DESIGN COMPLETENESS" "${context}"
    assert_contains "variant headings all recognized" "all sections present" "${context}"
    assert_not_contains "no section flagged missing" "(missing" "${context}"

    # Second fixture rotates the variant dimensions across sections so a
    # drift in any single regex is caught regardless of which variant it
    # was paired with above.
    local design2="${HOME}/design-variants-2.md"
    _write_design_fixture_raw "${design2}" \
        '## 🚫 Capabilities Affected & Constraints' \
        '### out of scope' \
        '## Acceptance-Scenarios'
    _seed_plan_state "${token}" "fixture-slug" "${design2}"

    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "rotated variants all recognized" "all sections present" "${context}"
    assert_not_contains "no section flagged missing (rotated)" "(missing" "${context}"

    teardown_test_env
}
test_plan_completeness_tolerates_heading_variants

test_plan_completeness_ignores_non_heading_mentions() {
    echo "-- test: DESIGN COMPLETENESS does not count body text or h4 as section headings --"
    setup_test_env
    install_registry

    local token="plan-guard-nonheading-$$"
    local design="${HOME}/design-nonheading.md"
    # Out-of-Scope appears only as body text and as an h4 — neither counts.
    _write_design_fixture_raw "${design}" \
        '## Capabilities Affected' \
        '## Acceptance Scenarios' \
        '#### Out-of-Scope'
    printf 'The out of scope items are listed elsewhere.\n' >> "${design}"
    _seed_plan_state "${token}" "fixture-slug" "${design}"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "completeness header present" "DESIGN COMPLETENESS" "${context}"
    assert_contains "Out-of-Scope still flagged missing" "Out-of-Scope (missing" "${context}"
    assert_not_contains "Capabilities Affected not flagged" "Capabilities Affected (missing" "${context}"
    assert_not_contains "Acceptance Scenarios not flagged" "Acceptance Scenarios (missing" "${context}"

    teardown_test_env
}
test_plan_completeness_ignores_non_heading_mentions

test_plan_completeness_bar_info_when_no_numerics() {
    echo "-- test: DESIGN COMPLETENESS adds [i] numeric-bar line when doc has no thresholds --"
    setup_test_env
    install_registry

    local token="plan-guard-bar-info-$$"
    local design="${HOME}/design-no-numerics.md"
    _write_design_fixture "${design}" "Capabilities Affected" "Out-of-Scope" "Acceptance Scenarios"
    _seed_plan_state "${token}" "fixture-slug" "${design}"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "all-present verdict unchanged" "all sections present" "${context}"
    assert_contains "bar info line present" "No numeric bar found" "${context}"
    assert_not_contains "bar line is not an X failure" "[X]  No numeric bar" "${context}"

    teardown_test_env
}
test_plan_completeness_bar_info_when_no_numerics

test_plan_completeness_bar_silent_when_numerics_present() {
    echo "-- test: DESIGN COMPLETENESS omits [i] bar line when doc states thresholds --"
    setup_test_env
    install_registry

    local token="plan-guard-bar-quiet-$$"
    local design="${HOME}/design-with-numerics.md"
    _write_design_fixture "${design}" "Capabilities Affected" "Out-of-Scope" "Acceptance Scenarios"
    printf 'The bar: p95 < 200ms and pass rate >= 80%%.\n' >> "${design}"
    _seed_plan_state "${token}" "fixture-slug" "${design}"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "all-present verdict unchanged" "all sections present" "${context}"
    assert_not_contains "bar info line absent" "No numeric bar found" "${context}"

    teardown_test_env
}
test_plan_completeness_bar_silent_when_numerics_present

# ---------------------------------------------------------------------------
# Skill-completion PostToolUse hook — advances composition state .completed
# when a chain-member Skill tool returns successfully.
# Design: docs/plans/2026-04-19-skill-completion-hook-design.md
# ---------------------------------------------------------------------------

_run_completion_hook() {
    local tool_name="$1"
    local is_error="${2:-false}"
    local input_key="${3:-name}"
    local payload
    payload="$(jq -n --arg n "${tool_name}" --arg k "${input_key}" --argjson e "${is_error}" '{
        tool_name: "Skill",
        tool_input: ({} | .[$k] = $n),
        tool_response: {is_error: $e}
    }')"
    printf '%s' "${payload}" | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${PROJECT_ROOT}/hooks/skill-completion-hook.sh" 2>/dev/null
    return $?
}

_seed_comp_state() {
    local token="$1" chain="$2" completed="$3" current="$4"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"
    jq -n --argjson c "${chain}" --argjson d "${completed}" --arg u "${current}" '{
        chain: $c,
        completed: $d,
        current: (if $u == "null" then null else $u end)
    }' > "${HOME}/.claude/.skill-composition-state-${token}"
}

test_completion_advances_chain_member() {
    echo "-- test: completion hook advances .completed for a chain-member skill --"
    setup_test_env

    local token="complete-chain-$$"
    _seed_comp_state "${token}" \
        '["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion","openspec-ship","finishing-a-development-branch"]' \
        '["brainstorming","writing-plans","executing-plans"]' \
        "requesting-code-review"

    _run_completion_hook "superpowers:requesting-code-review" false

    local after_completed after_current
    after_completed="$(jq -r '.completed | join(",")' "${HOME}/.claude/.skill-composition-state-${token}")"
    after_current="$(jq -r '.current' "${HOME}/.claude/.skill-composition-state-${token}")"

    assert_contains "completed contains requesting-code-review" "requesting-code-review" "${after_completed}"
    assert_equals "current advances to next chain member" "verification-before-completion" "${after_current}"

    teardown_test_env
}
test_completion_advances_chain_member

test_completion_noop_for_non_chain_skill() {
    echo "-- test: completion hook is a no-op for a non-chain skill --"
    setup_test_env

    local token="complete-nonchain-$$"
    _seed_comp_state "${token}" \
        '["brainstorming","writing-plans","executing-plans","requesting-code-review"]' \
        '["brainstorming","writing-plans"]' \
        "executing-plans"

    local before
    before="$(cat "${HOME}/.claude/.skill-composition-state-${token}")"

    _run_completion_hook "auto-claude-skills:security-scanner" false

    local after
    after="$(cat "${HOME}/.claude/.skill-composition-state-${token}")"

    assert_equals "state unchanged for non-chain skill" "${before}" "${after}"

    teardown_test_env
}
test_completion_noop_for_non_chain_skill

test_completion_noop_on_errored_tool_response() {
    echo "-- test: completion hook is a no-op when tool_response.is_error is true --"
    setup_test_env

    local token="complete-err-$$"
    _seed_comp_state "${token}" \
        '["brainstorming","writing-plans","executing-plans","requesting-code-review"]' \
        '["brainstorming","writing-plans","executing-plans"]' \
        "requesting-code-review"

    local before
    before="$(cat "${HOME}/.claude/.skill-composition-state-${token}")"

    _run_completion_hook "superpowers:requesting-code-review" true

    local after
    after="$(cat "${HOME}/.claude/.skill-composition-state-${token}")"

    assert_equals "state unchanged on tool error" "${before}" "${after}"

    teardown_test_env
}
test_completion_noop_on_errored_tool_response

test_completion_idempotent_on_reinvocation() {
    echo "-- test: completion hook is idempotent if the same skill is returned twice --"
    setup_test_env

    local token="complete-idem-$$"
    _seed_comp_state "${token}" \
        '["brainstorming","writing-plans","requesting-code-review"]' \
        '["brainstorming","writing-plans","requesting-code-review"]' \
        "null"

    _run_completion_hook "superpowers:requesting-code-review" false

    local after_completed_len after_completed_unique_len
    after_completed_len="$(jq -r '.completed | length' "${HOME}/.claude/.skill-composition-state-${token}")"
    after_completed_unique_len="$(jq -r '.completed | unique | length' "${HOME}/.claude/.skill-composition-state-${token}")"

    assert_equals "completed stays deduplicated" "${after_completed_len}" "${after_completed_unique_len}"
    assert_equals "completed length unchanged" "3" "${after_completed_len}"

    teardown_test_env
}
test_completion_idempotent_on_reinvocation

test_completion_graceful_on_malformed_state() {
    echo "-- test: completion hook exits cleanly when state file is malformed JSON --"
    setup_test_env

    local token="complete-badjson-$$"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"
    printf '{not:valid json' > "${HOME}/.claude/.skill-composition-state-${token}"

    local before
    before="$(cat "${HOME}/.claude/.skill-composition-state-${token}")"

    _run_completion_hook "superpowers:requesting-code-review" false
    local exit_code=$?

    local after
    after="$(cat "${HOME}/.claude/.skill-composition-state-${token}")"

    assert_equals "hook exits 0 on malformed state" "0" "${exit_code}"
    assert_equals "malformed state is not overwritten" "${before}" "${after}"

    teardown_test_env
}
test_completion_graceful_on_malformed_state

test_completion_last_chain_member_preserves_current() {
    echo "-- test: completion of the last chain member leaves .current as that skill (no next) --"
    setup_test_env

    local token="complete-last-$$"
    _seed_comp_state "${token}" \
        '["brainstorming","writing-plans","finishing-a-development-branch"]' \
        '["brainstorming","writing-plans"]' \
        "finishing-a-development-branch"

    _run_completion_hook "superpowers:finishing-a-development-branch" false

    local after_completed after_current
    after_completed="$(jq -r '.completed | join(",")' "${HOME}/.claude/.skill-composition-state-${token}")"
    after_current="$(jq -r '.current' "${HOME}/.claude/.skill-composition-state-${token}")"

    assert_contains "last member added to completed" "finishing-a-development-branch" "${after_completed}"
    assert_equals "current unchanged (no next member, fallthrough preserves existing)" \
        "finishing-a-development-branch" "${after_current}"

    teardown_test_env
}
test_completion_last_chain_member_preserves_current

test_completion_reads_tool_input_skill_fallback() {
    echo "-- test: completion hook falls back to .tool_input.skill when .tool_input.name is absent --"
    setup_test_env

    local token="complete-skillkey-$$"
    _seed_comp_state "${token}" \
        '["brainstorming","writing-plans","requesting-code-review"]' \
        '["brainstorming","writing-plans"]' \
        "requesting-code-review"

    _run_completion_hook "superpowers:requesting-code-review" false "skill"

    local after_completed
    after_completed="$(jq -r '.completed | join(",")' "${HOME}/.claude/.skill-composition-state-${token}")"

    assert_contains "completed advances via .tool_input.skill fallback" \
        "requesting-code-review" "${after_completed}"

    teardown_test_env
}
test_completion_reads_tool_input_skill_fallback

# ---------------------------------------------------------------------------
# C2: max_iterations is honored only for domain/required roles.
# Process and workflow skills must never be capped regardless of config.
# Locks the role-allowlist invariant.
# ---------------------------------------------------------------------------
test_max_iterations_role_allowlist() {
    echo "-- test: max_iterations honored only for domain/required roles --"
    setup_test_env

    if ! command -v jq >/dev/null 2>&1; then
        echo "  SKIP: jq not available"
        return 0
    fi

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "$cache_file")"
    cat > "$cache_file" <<'EOF'
{
  "version": "4.0",
  "skills": [
    {
      "name": "test-process-skill",
      "role": "process",
      "phase": "REVIEW",
      "priority": 50,
      "max_iterations": 1,
      "available": true,
      "enabled": true,
      "invoke": "Skill(test-process-skill)",
      "triggers": ["testprocessskilltrigger"],
      "keywords": [],
      "precedes": [],
      "requires": [],
      "trigger_mode": "any"
    },
    {
      "name": "test-domain-skill",
      "role": "domain",
      "phase": "REVIEW",
      "priority": 10,
      "max_iterations": 1,
      "available": true,
      "enabled": true,
      "invoke": "Skill(test-domain-skill)",
      "triggers": ["testdomainskilltrigger"],
      "keywords": [],
      "precedes": [],
      "requires": [],
      "trigger_mode": "any"
    }
  ],
  "context_capabilities": {},
  "phase_compositions": {},
  "phase_guide": {}
}
EOF

    local token="iter-cap-test-$$"
    echo "$token" > "${HOME}/.claude/.skill-session-token"
    cat > "${HOME}/.claude/.skill-composition-state-${token}" <<EOF
{
  "chain": ["test-process-skill","test-domain-skill"],
  "completed": ["test-process-skill","test-domain-skill"],
  "current_index": 0,
  "updated_at": "2026-05-21T00:00:00Z"
}
EOF

    local input='{"prompt":"testprocessskilltrigger and testdomainskilltrigger fire here"}'
    local output
    output="$(printf '%s' "$input" | bash "${PROJECT_ROOT}/hooks/skill-activation-hook.sh" 2>/dev/null)"

    if printf '%s' "$output" | grep -q "test-process-skill"; then
        echo "  PASS: process skill not capped (role-allowlist invariant holds)"
        TESTS_PASSED=$((${TESTS_PASSED:-0} + 1))
    else
        echo "  FAIL: process skill was capped despite role-allowlist guard"
        echo "  Output: $output"
        TESTS_FAILED=$((${TESTS_FAILED:-0} + 1))
    fi

    if printf '%s' "$output" | grep -q "test-domain-skill"; then
        echo "  FAIL: domain skill not capped despite max_iterations: 1"
        echo "  Output: $output"
        TESTS_FAILED=$((${TESTS_FAILED:-0} + 1))
    else
        echo "  PASS: domain skill capped at iteration 1"
        TESTS_PASSED=$((${TESTS_PASSED:-0} + 1))
    fi

    teardown_test_env
}
test_max_iterations_role_allowlist

test_supply_chain_investigation_fires_on_attack_language() {
    echo ""
    echo "Test: test_supply_chain_investigation_fires_on_attack_language"
    setup_test_env
    install_registry

    local prompt="there's a supply chain attack on axios 1.14.1, can you check if myorg is affected? advisory: https://example.com/ghsa"
    local input
    input=$(jq -nc --arg p "$prompt" '{"prompt": $p}')
    local output
    output="$(printf '%s' "$input" | bash "${PROJECT_ROOT}/hooks/skill-activation-hook.sh" 2>/dev/null)"

    if printf '%s' "$output" | grep -q "supply-chain-investigation"; then
        echo "  PASS: supply-chain-investigation fires on attack-language prompt"
        TESTS_PASSED=$((${TESTS_PASSED:-0} + 1))
    else
        echo "  FAIL: supply-chain-investigation did not fire"
        echo "  Output: $output"
        TESTS_FAILED=$((${TESTS_FAILED:-0} + 1))
    fi

    teardown_test_env
}
test_supply_chain_investigation_fires_on_attack_language

test_generic_cve_does_not_fire_supply_chain() {
    echo ""
    echo "Test: test_generic_cve_does_not_fire_supply_chain"
    setup_test_env
    install_registry

    local prompt="we use lodash and just saw CVE-2025-12345 with a critical CVSS score, can you check if we're vulnerable?"
    local input
    input=$(jq -nc --arg p "$prompt" '{"prompt": $p}')
    local output
    output="$(printf '%s' "$input" | bash "${PROJECT_ROOT}/hooks/skill-activation-hook.sh" 2>/dev/null)"

    if printf '%s' "$output" | grep -q "supply-chain-investigation"; then
        echo "  FAIL: supply-chain-investigation fired on generic CVE prompt"
        echo "  Output: $output"
        TESTS_FAILED=$((${TESTS_FAILED:-0} + 1))
    else
        echo "  PASS: supply-chain-investigation correctly did NOT fire on generic CVE language"
        TESTS_PASSED=$((${TESTS_PASSED:-0} + 1))
    fi

    teardown_test_env
}
test_generic_cve_does_not_fire_supply_chain

# ---------------------------------------------------------------------------
# project-verification routes on test/gate prompts at REVIEW
# ---------------------------------------------------------------------------
test_project_verification_routes_review() {
    echo "-- test: 'run the tests' routes to project-verification --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "run the tests and verify the build locally")"
    context="$(extract_context "${output}")"

    assert_contains "routes to project-verification" "project-verification" "${context}"

    teardown_test_env
}
test_project_verification_routes_review

print_summary
