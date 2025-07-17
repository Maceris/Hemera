#pragma once

#include <condition_variable>
#include <mutex>
#include <queue>

namespace hemera {

	template <typename T>
	struct ThreadSafeQueue {
		ThreadSafeQueue() = default;
		ThreadSafeQueue(const ThreadSafeQueue&) = delete;
		ThreadSafeQueue& operator=(const ThreadSafeQueue&) = delete;
		~ThreadSafeQueue() = default;

		void enqueue(T&& data) {
			std::lock_guard<std::mutex> lock(mutex);
			queue.push(std::forward(data));
			condition.notify_one();
		}

		void enqueue_array(T* data, size_t count) {
			std::lock_guard<std::mutex> lock(mutex);
			for (size_t i = 0; i < count; ++i) {
				queue.push(*(data + i));
			}
			condition.notify_one();
		}

		T dequeue() {
			std::unique_lock<std::mutex> lock(mutex);
			while (queue.empty()) {
				condition.wait(lock);
			}
			T result = queue.front();
			queue.pop();
			return result;
		}
		
		bool empty() const {
			return queue.empty();
		}

	private:
		std::queue<T> queue;
		std::mutex mutex;
		std::condition_variable condition;
	};
}