## The Para Studio "desk" (chat turns and Check/Save/Backup steps) written in eversince's vocabulary.
## Rules follow PDepaula/parastudio at ed1d254: one turn per game, one step at a time over all
## games, a step and a turn of the same game never together (line references are in the design notes, not in this repo).
## This module is the functional core: no thread, no lock, no process, no clock.

import std/[os, strutils]
import eversince

record ChatLine:
  game: string
  who: string
  text: string
record RunningTurn:
  game: string
  turn: int
record AgentPick:
  game: string
  agent: string

event MessageSent:
  game: string
  text: string
event TurnStarted:
  game: string
  turn: int
  agent: string
event Said:
  game: string
  turn: int
  text: string
event StopRequested:
  game: string
  turn: int
event TurnEnded:
  game: string
  turn: int
  outcome: string
event StepStarted:
  game: string
  step: int
  kind: string
event StepEnded:
  step: int
  code: int
event ConversationCleared:
  game: string
event AgentPicked:
  game: string
  agent: string

view Desk:
  state:
    running: seq[RunningTurn]
    lastTurn: int
    stepRunning: bool
    stepId: int
    stepKind: string
    stepGame: string
    lastStepCode: int
    picks: seq[AgentPick]
  on TurnStarted:
    state.running.add RunningTurn(game: e.game, turn: e.turn)
    state.lastTurn = e.turn
  on TurnEnded:
    var kept: seq[RunningTurn]
    for t in state.running:
      if t.turn != e.turn: kept.add t
    state.running = kept
    when defined(negView): state.stepGame = getEnv("HOME")
  on StepStarted:
    state.stepRunning = true
    state.stepId = e.step
    state.stepKind = e.kind
    state.stepGame = e.game
  on StepEnded:
    state.stepRunning = false
    state.lastStepCode = e.code
  on AgentPicked:
    var kept: seq[AgentPick]
    for p in state.picks:
      if p.game != e.game: kept.add p
    kept.add AgentPick(game: e.game, agent: e.agent)
    state.picks = kept

# Plain helpers are plain funcs: nothing special, usable from any decide or answer.
func turnOf(desk: Desk, game: string): int =
  ## The running turn of `game`, 0 when none runs.
  for t in desk.running:
    if t.game == game: return t.turn

func agentOf(desk: Desk, game: string): string =
  result = "claude"
  for p in desk.picks:
    if p.game == game: result = p.agent

view Chat:
  state:
    lines: seq[ChatLine]
  on MessageSent:
    state.lines.add ChatLine(game: e.game, who: "you", text: e.text)
  on Said:
    state.lines.add ChatLine(game: e.game, who: "producer", text: e.text)
  on TurnEnded:
    if e.outcome != "ok":
      state.lines.add ChatLine(game: e.game, who: "studio", text: "turn " & e.outcome)
  on AgentPicked:
    state.lines.add ChatLine(game: e.game, who: "studio", text: "producer is now " & e.agent)
  on ConversationCleared:
    var kept: seq[ChatLine]
    for l in state.lines:
      if l.game != e.game: kept.add l
    state.lines = kept

command SendMessage:
  fields:
    game: string
    text: string
  reads Desk
  produces MessageSent, TurnStarted
  refuses busy, badMessage
  decide:
    if cmd.text.strip.len == 0: refuse badMessage, "Write a message first."
    if cmd.text.len > 8000: refuse badMessage, "That message is too long."
    if desk.stepRunning and desk.stepGame == cmd.game:
      refuse busy, "A step (Check, Save or Backup) is still running."
    if desk.turnOf(cmd.game) != 0:
      refuse busy, "The producer is still working on this game's last message."
    emit MessageSent(game: cmd.game, text: cmd.text.strip)
    emit TurnStarted(game: cmd.game, turn: desk.lastTurn + 1, agent: desk.agentOf(cmd.game))
    when defined(negEmit): emit StepEnded(step: 1, code: 0)
    when defined(negClock): echo "now"
    when defined(negEnv): discard getEnv("HOME")

command StopTurn:
  fields:
    game: string
  reads Desk
  produces StopRequested
  refuses noTurn
  decide:
    if desk.turnOf(cmd.game) == 0: refuse noTurn, "No turn is running for this game."
    emit StopRequested(game: cmd.game, turn: desk.turnOf(cmd.game))

command RecordSay:
  fields:
    game: string
    turn: int
    text: string
  reads Desk
  produces Said
  refuses staleTurn
  decide:
    if desk.turnOf(cmd.game) != cmd.turn: refuse staleTurn, "That turn is over."
    emit Said(game: cmd.game, turn: cmd.turn, text: cmd.text)

command EndTurn:
  fields:
    game: string
    turn: int
    outcome: string
  reads Desk
  produces TurnEnded
  refuses staleTurn
  decide:
    if desk.turnOf(cmd.game) != cmd.turn: refuse staleTurn, "That turn is over."
    emit TurnEnded(game: cmd.game, turn: cmd.turn, outcome: cmd.outcome)

command StartStep:
  fields:
    game: string
    kind: string
    message: string
  reads Desk
  produces StepStarted
  refuses busy, needsMessage
  decide:
    if cmd.kind == "save" and cmd.message.strip.len == 0:
      refuse needsMessage, "Write a few words about what changed, then save."
    if desk.turnOf(cmd.game) != 0: refuse busy, "The producer is working on " & cmd.game & " right now."
    if desk.stepRunning: refuse busy, "Another step is still running (" & desk.stepKind & ")."
    emit StepStarted(game: cmd.game, step: desk.stepId + 1, kind: cmd.kind)

command EndStep:
  fields:
    step: int
    code: int
  reads Desk
  produces StepEnded
  refuses staleStep
  decide:
    if not desk.stepRunning or cmd.step != desk.stepId: refuse staleStep, "That step is over."
    emit StepEnded(step: cmd.step, code: cmd.code)

command NewConversation:
  fields:
    game: string
  reads Desk
  produces ConversationCleared
  refuses busy
  decide:
    if desk.turnOf(cmd.game) != 0: refuse busy, "The producer is still working. Stop the turn first."
    emit ConversationCleared(game: cmd.game)

command PickAgent:
  fields:
    game: string
    agent: string
  reads Desk
  produces AgentPicked
  refuses busy, whichAgent
  decide:
    if cmd.agent notin ["claude", "codex"]: refuse whichAgent, "That is not one of the producers this studio knows."
    if desk.turnOf(cmd.game) != 0: refuse busy, "The producer is working on this game's last message."
    emit AgentPicked(game: cmd.game, agent: cmd.agent)

record ChatPage:
  running: bool
  next: int
  lines: seq[ChatLine]

query ChatSince:
  fields:
    game: string
    since: int
  reads Chat, Desk
  returns ChatPage
  answer:
    result.running = desk.turnOf(q.game) != 0
    result.next = chat.lines.len
    for i in q.since ..< chat.lines.len:
      if chat.lines[i].game == q.game: result.lines.add chat.lines[i]
    when defined(negQuery): chat.lines.setLen 0

query DeskState:
  reads Desk
  returns Desk
  answer: desk

# The imperative shell plugs in here: what really runs the agent and the child `para`.
var runAgent*: proc (game, text: string): seq[string] = proc (game, text: string): seq[string] = @[]
var runStep*: proc (game, kind: string): int = proc (game, kind: string): int = 0
var cancelAgent*: proc (turn: int) = proc (turn: int) = discard

processor TurnRunner:
  issues RecordSay, EndTurn
  on TurnStarted:
    for line in runAgent(e.game, ""):
      issue RecordSay(game: e.game, turn: e.turn, text: line)
    issue EndTurn(game: e.game, turn: e.turn, outcome: "ok")
    when defined(negIssue): issue StartStep(game: e.game, kind: "check", message: "")
  on StopRequested:
    cancelAgent(e.turn)

processor StepRunner:
  issues EndStep
  on StepStarted:
    issue EndStep(step: e.step, code: runStep(e.game, e.kind))

sealModel(DeskApp, currentSourcePath().parentDir / "desk.em")
