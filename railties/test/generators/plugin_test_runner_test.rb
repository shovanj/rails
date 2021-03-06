require 'tmpdir'
require 'abstract_unit'

class PluginTestRunnerTest < ActiveSupport::TestCase
  def setup
    @destination_root = Dir.mktmpdir('bukkits')
    Dir.chdir(@destination_root) { `bundle exec rails plugin new bukkits --skip-bundle` }
    plugin_file 'test/dummy/db/schema.rb', ''
  end

  def teardown
    FileUtils.rm_rf(@destination_root)
  end

  def test_run_single_file
    create_test_file 'foo'
    create_test_file 'bar'
    assert_match "1 runs, 1 assertions, 0 failures", run_test_command("test/foo_test.rb")
  end

  def test_run_multiple_files
    create_test_file 'foo'
    create_test_file 'bar'
    assert_match "2 runs, 2 assertions, 0 failures", run_test_command("test/foo_test.rb test/bar_test.rb")
  end

  def test_mix_files_and_line_filters
    create_test_file 'account'
    plugin_file 'test/post_test.rb', <<-RUBY
      require 'test_helper'

      class PostTest < ActiveSupport::TestCase
        def test_post
          puts 'PostTest'
          assert true
        end

        def test_line_filter_does_not_run_this
          assert true
        end
      end
    RUBY

    run_test_command('test/account_test.rb test/post_test.rb:4').tap do |output|
      assert_match 'AccountTest', output
      assert_match 'PostTest', output
      assert_match '2 runs, 2 assertions', output
    end
  end

  def test_multiple_line_filters
    create_test_file 'account'
    create_test_file 'post'

    run_test_command('test/account_test.rb:4 test/post_test.rb:4').tap do |output|
      assert_match 'AccountTest', output
      assert_match 'PostTest', output
    end
  end

  def test_line_filter_without_line_runs_all_tests
    create_test_file 'account'

    run_test_command('test/account_test.rb:').tap do |output|
      assert_match 'AccountTest', output
    end
  end

  def test_output_inline_by_default
    create_test_file 'post', pass: false

    output = run_test_command('test/post_test.rb')
    assert_match %r{Running:\n\nPostTest\nF\n\nwups!\n\nbin/test (/private)?#{plugin_path}/test/post_test.rb:6}, output
  end

  def test_only_inline_failure_output
    create_test_file 'post', pass: false

    output = run_test_command('test/post_test.rb')
    assert_match %r{Finished in.*\n\n1 runs, 1 assertions}, output
  end

  def test_fail_fast
    create_test_file 'post', pass: false

    assert_match(/Interrupt/,
      capture(:stderr) { run_test_command('test/post_test.rb --fail-fast') })
  end

  def test_raise_error_when_specified_file_does_not_exist
    error = capture(:stderr) { run_test_command('test/not_exists.rb') }
    assert_match(%r{cannot load such file.+test/not_exists\.rb}, error)
  end

  private
    def plugin_path
      "#{@destination_root}/bukkits"
    end

    def run_test_command(arguments)
      Dir.chdir(plugin_path) { `bin/test #{arguments}` }
    end

    def create_test_file(name, pass: true)
      plugin_file "test/#{name}_test.rb", <<-RUBY
        require 'test_helper'

        class #{name.camelize}Test < ActiveSupport::TestCase
          def test_truth
            puts "#{name.camelize}Test"
            assert #{pass}, 'wups!'
          end
        end
      RUBY
    end

    def plugin_file(path, contents, mode: 'w')
      FileUtils.mkdir_p File.dirname("#{plugin_path}/#{path}")
      File.open("#{plugin_path}/#{path}", mode) do |f|
        f.puts contents
      end
    end
end
