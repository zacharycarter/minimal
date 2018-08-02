import 
  random,
  locks,
  atomicswrapper,
  rtArray,
  shareddeque,
  circularallocator,
  job,
  mt

from mathutils import powerOfTwo         # Used in other modules in templates
from cpuinfo import countProcessors   # Count cores
from os import sleep

const MaxJobCount = 1024

when not defined(cpu32) and not defined(cpu64):
  {. fatal: "The scheduler can't work with this cpu bit size" .}

type ThreadInitInfo* = tuple[num: int, initialFunc: JobFunction, onFinished: ptr Job]

var
  jobAllocator* {.threadvar.}: CircAlloc[MaxJobCount,Job]
  workerThreadsActive*: RtArray[bool]
  numWorkerThread* {.threadvar.}: int
  workThreadQueues* : RtArray[SharedDeque[MaxJobCount,ptr Job]]
  workerThreads* : RtArray[Thread[ThreadInitInfo]]
  workerThreadsCount* : int
  sleepLine : Cond
  sleepLock : Lock
  initialJob* : JobFunction

#alignedVar(  schedRunning*,bool,1)
var schedRunning*: bool

template localThreadQueue*(): SharedDeque[MaxJobCount, ptr Job] =
  workThreadQueues[numWorkerThread]

template workerThreadActive*(): bool  =
  workerThreadsActive[numWorkerThread]

proc `workerThreadActive=`*(val:bool) =
  echo "Setting " & $numWorkerThread & " to " & $val
  workerThreadsActive[numWorkerThread] = val


proc Yield* () =
  sleepLine.wait(sleepLock)

proc newJob*(function: Jobfunction, parent: ptr Job) : ptr Job {.gcsafe.} =
  result = jobAllocator.alloc()
  result.initJob(parent, function)

proc newJob*(function: Jobfunction, parent: ptr Job, sons: int32) : ptr Job {.gcsafe.} =
  result = jobAllocator.alloc()
  result.initJob(parent, function, sons)


proc newJob*(function: Jobfunction): ptr Job {.gcSafe,inline.} =
  result = jobAllocator.alloc()
  result.initJob(function)

proc newJob* ( function: Jobfunction, sons: int32): ptr Job {.gcSafe,inline.} =
  result = jobAllocator.alloc()
  result.initJob(function, sons)

proc run* (self: ptr Job) =
  localThreadQueue.push(self)

# A wait dependency, is implemented later
proc getJob*(): ptr Job

proc wait* (job: ptr Job) =
  while not job.completed():
    var nextJob = getJob()
    if nextJob != nil:
      nextJob.execute



################################################################################
#     Scheduler                                                                #
################################################################################

proc getJob(): ptr Job =
  result = localThreadQueue.pop()
  if result.isEmpty:
    #Our queue is empty, so let's steal from others
    let randomIndex = rand(workerThreadsCount - 1)

    var stealQueue = workThreadQueues[randomIndex]
    if (addr stealQueue) == (addr localThreadQueue):
      #Don't try to steal from ourselves
      #Yield()
      return nil

    result = stealQueue.steal()
    if result.isEmpty:
      echo "couldn't steal"
      #We couldn't steal any job, let's just give our time
      #Yield()

      return nil
    echo "I stole!"

proc workerThreadProc(info: ThreadInitInfo) {.thread.} =
  #Init thread local vars
  jobAllocator.init()
  numWorkerThread = info.num

  # We are actually using numWorkerThread so it needs to be done first
  workerThreadActive = true

  localThreadQueue.push( newJob(info.initialFunc, info.onFinished) )

  #Start scheduling
  while workerThreadActive:
    let job = getJob()
    if job != nil:
      job.execute()
    else:
      Yield()

proc globalInit*()=
  randomize()
  sleepLine.initCond()
  sleepLock.initLock()
  workerThreadsCount = countProcessors()
  workThreadQueues = newRtArray[SharedDeque[MaxJobCount, ptr Job]](workerThreadsCount)
  workerThreads = newRtArray[Thread[ThreadInitInfo]]( workerThreadsCount )
  workerThreadsActive = newRtArray[bool]( workerThreadsCount )
  schedRunning = true

proc atLeastOneThreadRunning*(): bool =
  result = false
  for i in 0..workerThreadsCount: # If there's one true result wiil be true
    result = result or workerThreadsActive[i]


proc init*(threadInit: JobFunction,whenFinished: ptr Job, onFrameRender: Jobfunction) =
  initialJob = threadInit

  var threadNum: int
  for thread in mitems(workerThreads, workerThreadsCount - 1):

    createThread(thread, workerThreadProc, (threadNum,initialJob,whenFinished) )
    pinToCpu(thread, threadNum)
    inc threadNum

  while schedRunning and atLeastOneThreadRunning():
    sleep(16)
    sleepLine.signal()
    loadMainThreadJob( newMainThreadJob(onFrameRender) )
    mainThreadProcess()


proc addJob*(fp: Jobfunction, parent: ptr Job): ptr Job {.inline.} =
  result = newJob(fp, parent)
  localThreadQueue.push(result)

proc addJob*(fp: Jobfunction): ptr Job {.inline.}=
  result = newJob(fp)
  localThreadQueue.push(result)