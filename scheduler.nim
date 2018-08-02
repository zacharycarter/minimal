import 
  rtarray,
  shareddeque

type
  Job* = object

const maxJobCount = 1024

var
  numWorkerThread* {.threadvar.}: int
  workThreadQueues* : RtArray[SharedDeque[maxJobCount, ptr Job]]

template localThreadQueue*(): SharedDeque[maxJobCount, ptr Job] =
  workThreadQueues[numWorkerThread]

echo repr localThreadQueue()