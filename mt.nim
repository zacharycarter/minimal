import 
  job,
  wordqueue,
  freelist,
  atomicswrapper

const maxMainThreadJobs = 128

var
  jobPool: FreeList[Job] # Allocate the object and return the pointer
  pendingJobs: WordQueue[maxMainThreadJobs - 1, ptr Job]

proc newMainThreadJob*(fun: JobFunction): ptr Job =
  result = jobPool.tryGet()
  when defined(debug):
    if result == nil:
      raise newException(ValueError, "We got nil from the jobPool")

  result.initJob(fun)

proc newMainThreadJob*(fun: JobFunction,sons: int32): ptr Job =
  result = jobPool.tryGet()
  when defined(debug):
    if result == nil:
      raise newException(ValueError, "We got nil from the jobPool")

  result.initJob(fun, sons)

proc newMainThreadJob*(fun: JobFunction, parent: ptr Job): ptr Job=
  result = jobPool.tryGet()
  result.initJob(parent, fun)

proc newMainThreadJob*(fun: JobFunction, parent: ptr Job, sons: int32): ptr Job=
  result = jobPool.tryGet()
  result.initJob(parent, fun, sons)

proc deleteMainThreadJob*(job: ptr Job) =
  # A pointer to a Job is the same as the pointer to it's node because it's the
  # first thing inside the node
  jobPool.add(job)

proc mainThreadProcess*() =
  var job = pendingJobs.pop()

  while job != nil:
    execute(job) # Call callback
    deleteMainThreadJob(job)
    job = pendingJobs.pop() # Try to get callback

  # Put itself into the threadPool
  #threadPool.add(threadId())

proc initMainThreadProcess*() =
  jobPool.init(maxMainThreadJobs)
  pendingJobs.init()

proc loadMainThreadJob*(job: ptr Job) =
  pendingJobs.push(job)