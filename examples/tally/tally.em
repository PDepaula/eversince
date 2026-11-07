# tally.em: the smallest complete model. Blocks are checked against tally.nim by the compiler.
screen Counter | queries CurrentTotal | commands Count
slice count up : Counter -> Count -> Counted -> Tally -> CurrentTotal -> Counter

command Count by:int | reads Tally | produces Counted | refuses notPositive,tooMany
event Counted by:int
view Tally total:int | consumes Counted
query CurrentTotal | reads Tally | returns int
