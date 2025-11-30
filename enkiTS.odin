// Copyright (c) 2013 Doug Binks
//
// This software is provided 'as-is', without any express or implied
// warranty. In no event will the authors be held liable for any damages
// arising from the use of this software.
//
// Permission is granted to anyone to use this software for any purpose,
// including commercial applications, and to alter it and redistribute it
// freely, subject to the following restrictions:
//
// 1. The origin of this software must not be misrepresented; you must not
//    claim that you wrote the original software. If you use this software
//    in a product, an acknowledgement in the product documentation would be
//    appreciated but is not required.
// 2. Altered source versions must be plainly marked as such, and must not be
//    misrepresented as being the original software.
// 3. This notice may not be removed or altered from any source distribution.
package enkits

import "core:c"

foreign import lib "lib/enkiTS.lib"
_ :: lib

TaskScheduler      :: struct {}
TaskSet            :: struct {}
PinnedTask         :: struct {}
Completable        :: struct {}
Dependency         :: struct {}
CompletionAction   :: struct {}
TaskExecuteRange   :: proc "c" (start_: u32, end_: u32, threadnum_: u32, pArgs_: rawptr)
PinnedTaskExecute  :: proc "c" (pArgs_: rawptr)
CompletionFunction :: proc "c" (pArgs_: rawptr, threadNum_: u32)

// TaskScheduler implements several callbacks intended for profilers
ProfilerCallbackFunc :: proc "c" (threadnum_: u32)

ProfilerCallbacks :: struct {
	threadStart:                     ProfilerCallbackFunc,
	threadStop:                      ProfilerCallbackFunc,
	waitForNewTaskSuspendStart:      ProfilerCallbackFunc, // thread suspended waiting for new tasks
	waitForNewTaskSuspendStop:       ProfilerCallbackFunc, // thread unsuspended
	waitForTaskCompleteStart:        ProfilerCallbackFunc, // thread waiting for task completion
	waitForTaskCompleteStop:         ProfilerCallbackFunc, // thread stopped waiting
	waitForTaskCompleteSuspendStart: ProfilerCallbackFunc, // thread suspended waiting task completion
	waitForTaskCompleteSuspendStop:  ProfilerCallbackFunc, // thread unsuspended
}

// Custom allocator, set in enkiTaskSchedulerConfig. Also see ENKI_CUSTOM_ALLOC_FILE_AND_LINE for file_ and line_
AllocFunc :: proc "c" (align_: c.size_t, size_: c.size_t, userData_: rawptr, file_: cstring, line_: i32) -> rawptr
FreeFunc  :: proc "c" (ptr_: rawptr, size_: c.size_t, userData_: rawptr, file_: cstring, line_: i32)

@(default_calling_convention="c", link_prefix="enki")
foreign lib {
	DefaultAllocFunc :: proc(align_: c.size_t, size_: c.size_t, userData_: rawptr, file_: cstring, line_: i32) -> rawptr ---
	DefaultFreeFunc  :: proc(ptr_: rawptr, size_: c.size_t, userData_: rawptr, file_: cstring, line_: i32) ---
}

CustomAllocator :: struct {
	alloc:    AllocFunc,
	free:     FreeFunc,
	userData: rawptr,
}

ParamsTaskSet :: struct {
	pArgs:    rawptr,
	setSize:  u32,
	minRange: u32,
	priority: i32,
}

ParamsPinnedTask :: struct {
	pArgs:    rawptr,
	priority: i32,
}

ParamsCompletionAction :: struct {
	pArgsPreComplete:  rawptr,
	pArgsPostComplete: rawptr,
	pDependency:       ^Completable, // task which when complete triggers completion function
}

// enkiTaskSchedulerConfig - configuration struct for advanced Initialize
// Always use enkiGetTaskSchedulerConfig() to get defaults prior to altering and
// initializing with enkiInitTaskSchedulerWithConfig().
TaskSchedulerConfig :: struct {
	// numTaskThreadsToCreate - Number of tasking threads the task scheduler will create. Must be > 0.
	// Defaults to GetNumHardwareThreads()-1 threads as thread which calls initialize is thread 0.
	numTaskThreadsToCreate: u32,

	// numExternalTaskThreads - Advanced use. Number of external threads which need to use TaskScheduler API.
	// See TaskScheduler::RegisterExternalTaskThread() for usage.
	// Defaults to 0. The thread used to initialize the TaskScheduler can also use the TaskScheduler API.
	// Thus there are (numTaskThreadsToCreate + numExternalTaskThreads + 1) able to use the API, with this
	// defaulting to the number of hardware threads available to the system.
	numExternalTaskThreads: u32,
	profilerCallbacks:      ProfilerCallbacks,
	customAllocator:        CustomAllocator,
}

@(default_calling_convention="c", link_prefix="enki")
foreign lib {
	/* ----------------------------  Task Scheduler  ---------------------------- */
	// Create a new task scheduler
	NewTaskScheduler :: proc() -> ^TaskScheduler ---

	// Create a new task scheduler using a custom allocator
	// This will  use the custom allocator to allocate the task scheduler struct
	// and additionally will set the custom allocator in enkiTaskSchedulerConfig of the task scheduler
	NewTaskSchedulerWithCustomAllocator :: proc(customAllocator_: CustomAllocator) -> ^TaskScheduler ---

	// Get config. Can be called before enkiInitTaskSchedulerWithConfig to get the defaults
	GetTaskSchedulerConfig :: proc(pETS_: ^TaskScheduler) -> TaskSchedulerConfig ---

	// DEPRECATED: use GetIsShutdownRequested() instead of GetIsRunning() in external code
	// while( enkiGetIsRunning(pETS) ) {} can be used in tasks which loop, to check if enkiTS has been shutdown.
	// If enkiGetIsRunning() returns false should then exit. Not required for finite tasks
	GetIsRunning :: proc(pETS_: ^TaskScheduler) -> i32 ---

	// while( !enkiGetIsShutdownRequested() ) {} can be used in tasks which loop, to check if enkiTS has been requested to shutdown.
	// If enkiGetIsShutdownRequested() returns true should then exit. Not required for finite tasks
	// Safe to use with enkiWaitforAllAndShutdown() where this will be set
	// Not safe to use with enkiWaitforAll(), use enkiGetIsWaitforAllCalled() instead.
	GetIsShutdownRequested :: proc(pETS_: ^TaskScheduler) -> i32 ---

	// while( !enkiGetIsWaitforAllCalled() ) {} can be used in tasks which loop, to check if enkiWaitforAll() has been called.
	// If enkiGetIsWaitforAllCalled() returns false should then exit. Not required for finite tasks
	// This is intended to be used with code which calls enkiWaitforAll().
	// This is also set when the task manager is shutting down, so no need to have an additional check for enkiGetIsShutdownRequested()
	GetIsWaitforAllCalled :: proc(pETS_: ^TaskScheduler) -> i32 ---

	// Initialize task scheduler - will create GetNumHardwareThreads()-1 threads, which is
	// sufficient to fill the system when including the main thread.
	// Initialize can be called multiple times - it will wait for completion
	// before re-initializing.
	InitTaskScheduler     :: proc(pETS_: ^TaskScheduler) ---
	GetNumHardwareThreads :: proc() -> u32 ---

	// Initialize a task scheduler with numThreads_ (must be > 0)
	// will create numThreads_-1 threads, as thread 0 is
	// the thread on which the initialize was called.
	InitTaskSchedulerNumThreads :: proc(pETS_: ^TaskScheduler, numThreads_: u32) ---

	// Initialize a task scheduler with config, see enkiTaskSchedulerConfig for details
	InitTaskSchedulerWithConfig :: proc(pETS_: ^TaskScheduler, config_: TaskSchedulerConfig) ---

	// Waits for all task sets to complete and shutdown threads - not guaranteed to work unless we know we
	// are in a situation where tasks aren't being continuously added.
	// pETS_ can then be reused.
	// This function can be safely called even if enkiInit* has not been called.
	WaitforAllAndShutdown :: proc(pETS_: ^TaskScheduler) ---

	// Delete a task scheduler.
	DeleteTaskScheduler :: proc(pETS_: ^TaskScheduler) ---

	// Waits for all task sets to complete - not guaranteed to work unless we know we
	// are in a situation where tasks aren't being continuously added.
	WaitForAll :: proc(pETS_: ^TaskScheduler) ---

	// Returns the number of threads created for running tasks + number of external threads
	// plus 1 to account for the thread used to initialize the task scheduler.
	// Equivalent to config values: numTaskThreadsToCreate + numExternalTaskThreads + 1.
	// It is guaranteed that enkiGetThreadNum() < enkiGetNumTaskThreads()
	GetNumTaskThreads :: proc(pETS_: ^TaskScheduler) -> u32 ---

	// Returns the current task threadNum.
	// Will return 0 for thread which initialized the task scheduler,
	// and ENKI_NO_THREAD_NUM for all other non-enkiTS threads which have not been registered ( see enkiRegisterExternalTaskThread() ),
	// and < enkiGetNumTaskThreads() for all registered and internal enkiTS threads.
	// It is guaranteed that enkiGetThreadNum() < enkiGetNumTaskThreads() unless it is ENKI_NO_THREAD_NUM
	GetThreadNum :: proc(pETS_: ^TaskScheduler) -> u32 ---

	// Call on a thread to register the thread to use the TaskScheduling API.
	// This is implicitly done for the thread which initializes the TaskScheduler
	// Intended for developers who have threads who need to call the TaskScheduler API
	// Returns true if successful, false if not.
	// Can only have numExternalTaskThreads registered at any one time, which must be set
	// at initialization time.
	RegisterExternalTaskThread :: proc(pETS_: ^TaskScheduler) -> i32 ---

	// As enkiRegisterExternalTaskThread() but explicitly requests a given thread number.
	// threadNumToRegister_ must be  >= GetNumFirstExternalTaskThread()
	// and < ( GetNumFirstExternalTaskThread() + numExternalTaskThreads )
	RegisterExternalTaskThreadNum :: proc(pETS_: ^TaskScheduler, threadNumToRegister_: u32) -> i32 ---

	// Call on a thread on which RegisterExternalTaskThread has been called to deregister that thread.
	DeRegisterExternalTaskThread :: proc(pETS_: ^TaskScheduler) ---

	// Get the number of registered external task threads.
	GetNumRegisteredExternalTaskThreads :: proc(pETS_: ^TaskScheduler) -> u32 ---

	// Get the thread number of the first external task thread. This thread
	// is not guaranteed to be registered, but threads are registered in order
	// from GetNumFirstExternalTaskThread() up to ( GetNumFirstExternalTaskThread() + numExternalTaskThreads )
	// Note that if numExternalTaskThreads == 0 a for loop using this will be valid:
	// for( uint32_t externalThreadNum = GetNumFirstExternalTaskThread();
	//      externalThreadNum < ( GetNumFirstExternalTaskThread() + numExternalTaskThreads
	//      ++externalThreadNum ) { // do something with externalThreadNum }
	GetNumFirstExternalTaskThread :: proc() -> u32 ---

	/* ----------------------------     TaskSets    ---------------------------- */
	// Create a task set.
	CreateTaskSet :: proc(pETS_: ^TaskScheduler, taskFunc_: TaskExecuteRange) -> ^TaskSet ---

	// Delete a task set.
	DeleteTaskSet :: proc(pETS_: ^TaskScheduler, pTaskSet_: ^TaskSet) ---

	// Get task parameters via enkiParamsTaskSet
	GetParamsTaskSet :: proc(pTaskSet_: ^TaskSet) -> ParamsTaskSet ---

	// Set task parameters via enkiParamsTaskSet
	SetParamsTaskSet :: proc(pTaskSet_: ^TaskSet, params_: ParamsTaskSet) ---

	// Set task priority ( 0 to ENKITS_TASK_PRIORITIES_NUM-1, where 0 is highest)
	SetPriorityTaskSet :: proc(pTaskSet_: ^TaskSet, priority_: i32) ---

	// Set TaskSet args
	SetArgsTaskSet :: proc(pTaskSet_: ^TaskSet, pArgs_: rawptr) ---

	// Set TaskSet set setSize
	SetSetSizeTaskSet :: proc(pTaskSet_: ^TaskSet, setSize_: u32) ---

	// Set TaskSet set min range
	SetMinRangeTaskSet :: proc(pTaskSet_: ^TaskSet, minRange_: u32) ---

	// Schedule the task, use parameters set with enkiSet*TaskSet
	AddTaskSet :: proc(pETS_: ^TaskScheduler, pTaskSet_: ^TaskSet) ---

	// Schedule the task
	// overwrites args previously set with enkiSetArgsTaskSet
	// overwrites setSize previously set with enkiSetSetSizeTaskSet
	AddTaskSetArgs :: proc(pETS_: ^TaskScheduler, pTaskSet_: ^TaskSet, pArgs_: rawptr, setSize_: u32) ---

	// Schedule the task with a minimum range.
	// This should be set to a value which results in computation effort of at least 10k
	// clock cycles to minimize task scheduler overhead.
	// NOTE: The last partition will be smaller than m_MinRange if m_SetSize is not a multiple
	// of m_MinRange.
	// Also known as grain size in literature.
	AddTaskSetMinRange :: proc(pETS_: ^TaskScheduler, pTaskSet_: ^TaskSet, pArgs_: rawptr, setSize_: u32, minRange_: u32) ---

	// Check if TaskSet is complete. Doesn't wait. Returns 1 if complete, 0 if not.
	IsTaskSetComplete :: proc(pETS_: ^TaskScheduler, pTaskSet_: ^TaskSet) -> i32 ---

	// Wait for a given task.
	// should only be called from thread which created the task scheduler, or within a task
	// if called with 0 it will try to run tasks, and return if none available.
	// Only wait for child tasks of the current task otherwise a deadlock could occur.
	WaitForTaskSet :: proc(pETS_: ^TaskScheduler, pTaskSet_: ^TaskSet) ---

	// enkiWaitForTaskSetPriority as enkiWaitForTaskSet but only runs other tasks with priority <= maxPriority_
	// Only wait for child tasks of the current task otherwise a deadlock could occur.
	WaitForTaskSetPriority :: proc(pETS_: ^TaskScheduler, pTaskSet_: ^TaskSet, maxPriority_: i32) ---

	/* ----------------------------   PinnedTasks   ---------------------------- */
	// Create a pinned task.
	CreatePinnedTask :: proc(pETS_: ^TaskScheduler, taskFunc_: PinnedTaskExecute, threadNum_: u32) -> ^PinnedTask ---

	// Delete a pinned task.
	DeletePinnedTask :: proc(pETS_: ^TaskScheduler, pPinnedTask_: ^PinnedTask) ---

	// Get task parameters via enkiParamsTaskSet
	GetParamsPinnedTask :: proc(pTask_: ^PinnedTask) -> ParamsPinnedTask ---

	// Set task parameters via enkiParamsTaskSet
	SetParamsPinnedTask :: proc(pTask_: ^PinnedTask, params_: ParamsPinnedTask) ---

	// Set PinnedTask ( 0 to ENKITS_TASK_PRIORITIES_NUM-1, where 0 is highest)
	SetPriorityPinnedTask :: proc(pTask_: ^PinnedTask, priority_: i32) ---

	// Set PinnedTask args
	SetArgsPinnedTask :: proc(pTask_: ^PinnedTask, pArgs_: rawptr) ---

	// Schedule a pinned task
	// Pinned tasks can be added from any thread
	AddPinnedTask :: proc(pETS_: ^TaskScheduler, pTask_: ^PinnedTask) ---

	// Schedule a pinned task
	// Pinned tasks can be added from any thread
	// overwrites args previously set with enkiSetArgsPinnedTask
	AddPinnedTaskArgs :: proc(pETS_: ^TaskScheduler, pTask_: ^PinnedTask, pArgs_: rawptr) ---

	// This function will run any enkiPinnedTask* for current thread, but not run other
	// Main thread should call this or use a wait to ensure its tasks are run.
	RunPinnedTasks :: proc(pETS_: ^TaskScheduler) ---

	// Check if enkiPinnedTask is complete. Doesn't wait. Returns 1 if complete, 0 if not.
	IsPinnedTaskComplete :: proc(pETS_: ^TaskScheduler, pTask_: ^PinnedTask) -> i32 ---

	// Wait for a given pinned task.
	// should only be called from thread which created the task scheduler, or within a task
	// if called with 0 it will try to run tasks, and return if none available.
	// Only wait for child tasks of the current task otherwise a deadlock could occur.
	WaitForPinnedTask :: proc(pETS_: ^TaskScheduler, pTask_: ^PinnedTask) ---

	// enkiWaitForPinnedTaskPriority as enkiWaitForPinnedTask but only runs other tasks with priority <= maxPriority_
	// Only wait for child tasks of the current task otherwise a deadlock could occur.
	WaitForPinnedTaskPriority :: proc(pETS_: ^TaskScheduler, pTask_: ^PinnedTask, maxPriority_: i32) ---

	// Waits for the current thread to receive a PinnedTask
	// Will not run any tasks - use with RunPinnedTasks()
	// Can be used with both ExternalTaskThreads or with an enkiTS tasking thread to create
	// a thread which only runs pinned tasks. If enkiTS threads are used can create
	// extra enkiTS task threads to handle non blocking computation via normal tasks.
	WaitForNewPinnedTasks :: proc(pETS_: ^TaskScheduler) ---

	/* ----------------------------  Completables  ---------------------------- */
	// Get a pointer to an enkiCompletable from an enkiTaskSet.
	// Do not call enkiDeleteCompletable on the returned pointer.
	GetCompletableFromTaskSet :: proc(pTaskSet_: ^TaskSet) -> ^Completable ---

	// Get a pointer to an enkiCompletable from an enkiPinnedTask.
	// Do not call enkiDeleteCompletable on the returned pointer.
	GetCompletableFromPinnedTask :: proc(pPinnedTask_: ^PinnedTask) -> ^Completable ---

	// Get a pointer to an enkiCompletable from an enkiPinnedTask.
	// Do not call enkiDeleteCompletable on the returned pointer.
	GetCompletableFromCompletionAction :: proc(pCompletionAction_: ^CompletionAction) -> ^Completable ---

	// Create an enkiCompletable
	// Can be used with dependencies to wait for their completion.
	// Delete with enkiDeleteCompletable
	CreateCompletable :: proc(pETS_: ^TaskScheduler) -> ^Completable ---

	// Delete an enkiCompletable created with enkiCreateCompletable
	DeleteCompletable :: proc(pETS_: ^TaskScheduler, pCompletable_: ^Completable) ---

	// Wait for a given completable.
	// should only be called from thread which created the task scheduler, or within a task
	// if called with 0 it will try to run tasks, and return if none available.
	// Only wait for child tasks of the current task otherwise a deadlock could occur.
	WaitForCompletable :: proc(pETS_: ^TaskScheduler, pTask_: ^Completable) ---

	// enkiWaitForCompletablePriority as enkiWaitForCompletable but only runs other tasks with priority <= maxPriority_
	// Only wait for child tasks of the current task otherwise a deadlock could occur.
	WaitForCompletablePriority :: proc(pETS_: ^TaskScheduler, pTask_: ^Completable, maxPriority_: i32) ---

	/* ----------------------------   Dependencies  ---------------------------- */
	// Create an enkiDependency, used to set dependencies between tasks
	// Call enkiDeleteDependency to delete.
	CreateDependency :: proc(pETS_: ^TaskScheduler) -> ^Dependency ---

	// Delete an enkiDependency created with enkiCreateDependency.
	DeleteDependency :: proc(pETS_: ^TaskScheduler, pDependency_: ^Dependency) ---

	// Set a dependency between pDependencyTask_ and pTaskToRunOnCompletion_
	// such that when all dependencies of pTaskToRunOnCompletion_ are completed it will run.
	SetDependency :: proc(pDependency_: ^Dependency, pDependencyTask_: ^Completable, pTaskToRunOnCompletion_: ^Completable) ---

	/* -------------------------- Completion Actions --------------------------- */
	// Create a CompletionAction.
	// completionFunctionPreComplete_ - function called BEFORE the complete action task is 'complete', which means this is prior to dependent tasks being run.
	//                                  this function can thus alter any task arguments of the dependencies.
	// completionFunctionPostComplete_ - function called AFTER the complete action task is 'complete'. Dependent tasks may have already been started.
	//                                  This function can delete the completion action if needed as it will no longer be accessed by other functions.
	// It is safe to set either of these to NULL if you do not require that function
	CreateCompletionAction :: proc(pETS_: ^TaskScheduler, completionFunctionPreComplete_: CompletionFunction, completionFunctionPostComplete_: CompletionFunction) -> ^CompletionAction ---

	// Delete a CompletionAction.
	DeleteCompletionAction :: proc(pETS_: ^TaskScheduler, pCompletionAction_: ^CompletionAction) ---

	// Get task parameters via enkiParamsTaskSet
	GetParamsCompletionAction :: proc(pCompletionAction_: ^CompletionAction) -> ParamsCompletionAction ---

	// Set task parameters via enkiParamsTaskSet
	SetParamsCompletionAction :: proc(pCompletionAction_: ^CompletionAction, params_: ParamsCompletionAction) ---
}

