# desk.em: the Para Studio desk as an event model. Read top to bottom.
# The compiler checks every record/event/command/view/query/processor line against the code.
# Screens and slices exist only here; the compiler checks that they name real blocks and real edges.

# --- what the friend sees ---
screen ChatPanel  | queries ChatSince | commands SendMessage,StopTurn,NewConversation,PickAgent
screen StepsPanel | queries DeskState | commands StartStep

# --- the stories, one line each ---
slice send a message : ChatPanel -> SendMessage -> TurnStarted -> TurnRunner -> RecordSay -> Said -> Chat -> ChatSince -> ChatPanel
slice the turn ends  : TurnRunner -> EndTurn -> TurnEnded -> Desk -> ChatSince -> ChatPanel
slice stop a turn    : ChatPanel -> StopTurn -> StopRequested -> TurnRunner -> EndTurn -> TurnEnded -> Chat
slice run a step     : StepsPanel -> StartStep -> StepStarted -> StepRunner -> EndStep -> StepEnded -> Desk -> DeskState -> StepsPanel
slice pick a producer: ChatPanel -> PickAgent -> AgentPicked -> Desk -> SendMessage
slice start over     : ChatPanel -> NewConversation -> ConversationCleared -> Chat -> ChatSince -> ChatPanel

# --- requests ---
command SendMessage     game:string text:string             | reads Desk | produces MessageSent,TurnStarted | refuses busy,badMessage
command StopTurn        game:string                         | reads Desk | produces StopRequested           | refuses noTurn
command RecordSay       game:string turn:int text:string    | reads Desk | produces Said                    | refuses staleTurn
command EndTurn         game:string turn:int outcome:string | reads Desk | produces TurnEnded               | refuses staleTurn
command StartStep       game:string kind:string message:string | reads Desk | produces StepStarted          | refuses busy,needsMessage
command EndStep         step:int code:int                   | reads Desk | produces StepEnded               | refuses staleStep
command NewConversation game:string                         | reads Desk | produces ConversationCleared     | refuses busy
command PickAgent       game:string agent:string            | reads Desk | produces AgentPicked             | refuses busy,whichAgent

# --- facts ---
event MessageSent         game:string text:string
event TurnStarted         game:string turn:int agent:string
event Said                game:string turn:int text:string
event StopRequested       game:string turn:int
event TurnEnded           game:string turn:int outcome:string
event StepStarted         game:string step:int kind:string
event StepEnded           step:int code:int
event ConversationCleared game:string
event AgentPicked         game:string agent:string

# --- what is remembered ---
view Desk running:list[RunningTurn] lastTurn:int stepRunning:bool stepId:int stepKind:string stepGame:string lastStepCode:int picks:list[AgentPick] | consumes TurnStarted,TurnEnded,StepStarted,StepEnded,AgentPicked
view Chat lines:list[ChatLine] | consumes MessageSent,Said,TurnEnded,AgentPicked,ConversationCleared

# --- questions ---
query ChatSince game:string since:int | reads Chat,Desk | returns ChatPage
query DeskState                       | reads Desk      | returns Desk

# --- background work (the only blocks with side effects) ---
processor TurnRunner | consumes TurnStarted,StopRequested | issues RecordSay,EndTurn
processor StepRunner | consumes StepStarted               | issues EndStep

# --- value types ---
record ChatLine    game:string who:string text:string
record RunningTurn game:string turn:int
record AgentPick   game:string agent:string
record ChatPage    running:bool next:int lines:list[ChatLine]
