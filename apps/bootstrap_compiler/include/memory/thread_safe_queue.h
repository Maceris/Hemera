#pragma once

#include <concepts>
#include <condition_variable>
#include <mutex>
#include <queue>
#include <utility>

namespace hemera {

	template <typename T>
	struct ThreadSafeQueue {
		std::mutex mutex;

		ThreadSafeQueue() = default;
		ThreadSafeQueue(const ThreadSafeQueue&) = delete;
		ThreadSafeQueue& operator=(const ThreadSafeQueue&) = delete;
		~ThreadSafeQueue() = default;

		template <typename T>
		void enqueue(T&& data) {
			std::scoped_lock<std::mutex> lock(mutex);
			queue.push(std::forward<T>(data));
		}

		template <typename T>
		void enqueue_unsafe(T&& data) {
			queue.push(std::forward<T>(data));
		}

		template <typename T>
		T dequeue_or_else(T or_else) {
			std::scoped_lock<std::mutex> lock(mutex);

			if (queue.empty()) {
				return or_else;
			}

			T result = queue.front();
			queue.pop();
			return result;
		}
		
		bool empty() {
			std::scoped_lock<std::mutex> lock(mutex);
			return queue.empty();
		}

	private:
		std::queue<T> queue;
	};
}