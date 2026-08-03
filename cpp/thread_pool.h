#pragma once
#include <atomic>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

class ThreadPool {
public:
    explicit ThreadPool(int n) {
        for(int i=0;i<n;++i) workers_.emplace_back([this]{ worker(); });
    }
    ~ThreadPool(){ {std::lock_guard lock(mu_); stop_=true; ++generation_;} cv_.notify_all(); for(auto& t:workers_) t.join(); }
    void parallel_for(int count, std::function<void(int)> fn){
        {std::lock_guard lock(mu_); fn_=std::move(fn); count_=count; next_=0; remaining_=static_cast<int>(workers_.size()); ++generation_;}
        cv_.notify_all(); std::unique_lock lock(mu_); done_.wait(lock,[&]{return remaining_==0;});
    }
private:
    void worker(){int seen=0;for(;;){std::unique_lock lock(mu_);cv_.wait(lock,[&]{return stop_||generation_!=seen;});if(stop_)return;seen=generation_;lock.unlock();for(;;){int i=next_.fetch_add(1);if(i>=count_)break;fn_(i);}lock.lock();if(--remaining_==0)done_.notify_one();}}
    std::vector<std::thread> workers_; std::mutex mu_; std::condition_variable cv_,done_; std::function<void(int)> fn_;
    std::atomic<int> next_{0}; int count_=0,remaining_=0,generation_=0; bool stop_=false;
};

