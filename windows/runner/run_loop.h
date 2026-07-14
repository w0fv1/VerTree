#ifndef RUNNER_RUN_LOOP_H_
#define RUNNER_RUN_LOOP_H_

#include <flutter/flutter_engine.h>

#include <chrono>
#include <set>



class RunLoop {
 public:
  RunLoop();
  ~RunLoop();


  RunLoop(RunLoop const&) = delete;
  RunLoop& operator=(RunLoop const&) = delete;


  void Run();


  void RegisterFlutterInstance(
      flutter::FlutterEngine* flutter_instance);


  void UnregisterFlutterInstance(
      flutter::FlutterEngine* flutter_instance);

 private:
  using TimePoint = std::chrono::steady_clock::time_point;


  TimePoint ProcessFlutterMessages();

  std::set<flutter::FlutterEngine*> flutter_instances_;
};

#endif
