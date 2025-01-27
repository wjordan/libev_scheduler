# frozen_string_literal: true
require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/reporters'
require 'libev_scheduler'

class TestFiberMutex < MiniTest::Test
  def test_mutex_synchronize
    mutex = Mutex.new

    thread = Thread.new do
      scheduler = Libev::Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        assert !Fiber.blocking?

        mutex.synchronize do
          assert !Fiber.blocking?
        end
      end
    end

    thread.join
  end

  def test_mutex_interleaved_locking
    mutex = Mutex.new

    thread = Thread.new do
      scheduler = Libev::Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        mutex.lock
        sleep 0.1
        mutex.unlock
      end

      Fiber.schedule do
        mutex.lock
        sleep 0.1
        mutex.unlock
      end

      scheduler.run
    end

    thread.join
  end

  def test_mutex_thread
    mutex = Mutex.new
    mutex.lock

    thread = Thread.new do
      scheduler = Libev::Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        mutex.lock
        sleep 0.1
        mutex.unlock
      end

      scheduler.run
    end

    sleep 0.1
    mutex.unlock

    thread.join
  end

  def test_mutex_fiber_raise
    skip "stuck"
    mutex = Mutex.new
    ran = false

    main = Thread.new do
      p [1, :pre_lock]
      mutex.lock
      p [1, :post_lock]

      thread = Thread.new do
        scheduler = Libev::Scheduler.new
        Fiber.set_scheduler scheduler

        f = Fiber.schedule do
          assert_raise_message("bye") do
            p [2, :pre_lock]
            mutex.lock
            p [2, :post_lock]
          end

          ran = true
        end

        Fiber.schedule do
          p [3, :pre_raise]
          f.raise "bye"
          p [3, :post_raise]
        end
      end

      thread.join
    end

    main.join # causes mutex to be released
    assert_equal false, mutex.locked?
    assert_equal true, ran
  end

  def test_condition_variable
    mutex = Mutex.new
    condition = ConditionVariable.new

    signalled = 0

    Thread.new do
      scheduler = Libev::Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        mutex.synchronize do
          3.times do
            condition.wait(mutex)
            signalled += 1
          end
        end
      end

      Fiber.schedule do
        3.times do
          mutex.synchronize do
            condition.signal
          end

          sleep 0.1
        end
      end

      scheduler.run
    end.join

    assert_equal 3, signalled
  end

  def test_queue
    queue = Queue.new
    processed = 0

    thread = Thread.new do
      scheduler = Libev::Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        3.times do |i|
          queue << i
          sleep 0.1
        end

        queue.close
      end

      Fiber.schedule do
        while item = queue.pop
          processed += 1
        end
      end

      scheduler.run
    end

    thread.join

    assert_equal 3, processed
  end

  def test_queue_pop_waits
    queue = Queue.new
    running = false

    thread = Thread.new do
      scheduler = Libev::Scheduler.new
      Fiber.set_scheduler scheduler

      result = nil
      Fiber.schedule do
        result = queue.pop
      end

      running = true
      scheduler.run
      result
    end

    Thread.pass until running
    sleep 0.1

    queue << :done
    assert_equal :done, thread.value
  end

  def test_mutex_deadlock
    skip "no impl of assert_in_out_err"
    error_pattern = /No live threads left. Deadlock\?/

    assert_in_out_err %W[-I#{__dir__} -], <<-RUBY, ['in synchronize'], error_pattern, success: false
    require 'scheduler'
    mutex = Mutex.new

    thread = Thread.new do
      scheduler = Libev::Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        mutex.synchronize do
          puts 'in synchronize'
          Fiber.yield
        end
      end

      mutex.lock
    end

    thread.join
    RUBY
  end
end
