# mini.em: the model of tests/errors/mini.nim.
screen Counter | queries CurrentTotal | commands Count
slice count up : Counter -> Count -> Counted -> Tally -> CurrentTotal -> Counter
slice tidy up : Counted -> Notifier -> Clear -> Reset

command Count by:int | reads Tally | produces Counted | refuses notPositive
command Clear | reads Tally | produces Reset
event Counted by:int
event Reset to:int
view Tally total:int | consumes Counted,Reset
query CurrentTotal | reads Tally | returns int
processor Notifier | consumes Counted | issues Clear
