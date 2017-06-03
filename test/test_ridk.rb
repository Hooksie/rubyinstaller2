require "minitest/autorun"
require "tempfile"
require "yaml"
require "test/helper/msys"

module RidkTests
  include Helper::Msys

  def setup
    RubyInstaller::Runtime.disable_msys_apps
    @old_path = ENV['PATH']
  end

  def teardown
    ENV['PATH'] = @old_path
  end

  def test_ridk_enable
    skip unless File.directory?("C:/msys64")

    ENV['PATH'] += ';"c:\\testpath"'
    out = run_output_vars([], ["ridk enable"], %w[PATH MSYSTEM])

    mingw = RUBY_PLATFORM =~ /x64/ ? "MINGW64" : "MINGW32"
    assert_match(/PATH: .*;C:\\msys64\\#{mingw}\\bin;C:\\msys64\\usr\\bin.*;"c:\\testpath"$/i, out)
    assert_match(/MSYSTEM: #{mingw}/i, out)
  end

  def test_ridk_disable
    skip unless File.directory?("C:/msys64")

    out = run_output_vars([], ["ridk enable", "ridk disable"], %w[PATH MSYSTEM])

    refute_operator out.downcase, :include?, "c:\\msys64", "msys should be removed from the PATH"
    assert_operator out.downcase, :include?, "msystem: \n", "msystem should get deleted"
  end

  def test_ridk_help
    out = run_capture_output "ridk help"

    %w[install enable disable exec help version].each do |op|
      assert_operator out, :include?, op
    end
  end

  def test_ridk_exec
    out = run_capture_output "ridk exec pacman -h"

    assert_operator out, :include?, "pacman <operation>"
  end

  def test_ridk_version
    skip unless File.directory?("C:/msys64")

    puts "PATH-dirs:"
    ENV['PATH'].split(";").each{|d| p [d, Dir[d.gsub("\\","/")+"/*"]] }
    puts "PATH: #{ENV['PATH']}"
    p run_capture_output("echo %PATH%")

    out = run_capture_output "ridk version"
    y = YAML.load(out)

    refute_nil y["ruby"]["path"]
    assert_equal RUBY_VERSION, y["ruby"]["version"]
    assert_equal RUBY_PLATFORM, y["ruby"]["platform"]
    refute_nil y["ruby_installer"]["package_version"]
    refute_nil y["ruby_installer"]["git_commit"]
    assert_match(/gcc/, y["cc"])
    assert_match(/bash/, y["sh"])
    assert_equal "c:\\msys64", y["msys2"]["path"].downcase
    skip "Appveyors MSYS version is too old to have a components.xml" if ENV['APPVEYOR']
    assert_match(/MSYS/, y["msys2"]["title"])
    assert_match(/\d/, y["msys2"]["version"])
  end

  def test_ridk_version_without_msys
    out = simulate_no_msysdir do
      run_capture_output "ridk version"
    end
    y = YAML.load(out)

    assert_equal RUBY_VERSION, y["ruby"]["version"]
    assert_equal RUBY_PLATFORM, y["ruby"]["platform"]
    refute_nil y["ruby_installer"]["package_version"]
    refute_nil y["ruby_installer"]["git_commit"]
    assert_nil y["msys2"]
  end
end

class TestRidkCmd < Minitest::Test
  include Helper::Msys
  include RidkTests

  def vars_to_print(vars)
    vars.map do |var|
      "@echo #{var}: %#{var}%"
    end.join("\n")
  end

  def run_output_vars(before_vars, commands, after_vars)
    jc = commands.map do |c|
      "@call #{c} > NUL"
    end.join("\n")

    run_in_shells <<-EOCMD, nil
#{ vars_to_print(before_vars) }
#{ jc }
#{ vars_to_print(after_vars) }
    EOCMD
  end

  def run_capture_output(command)
    run_in_shells <<-EOCMD, nil
@call #{command}
    EOCMD
  end

  def run_in_shells(cmd, ps1)
    Tempfile.open(%w[test .cmd]) do |fd|
      fd.write(cmd)
      fd.close
      IO.popen(["cmd", "/c", fd.path]){|io| io.read }
    end
  end

  def test_ridk_install
    assert system("ridk install msys2 pacman_update")
  end
end

class TestRidkPs1 < Minitest::Test
  include Helper::Msys
  include RidkTests

  def vars_to_print(vars)
    vars.map do |var|
      "Write-Output ('#{var}: ' + $env:#{var})"
    end.join("\n")
  end

  def run_output_vars(before_vars, commands, after_vars)
    jc = commands.map do |c|
      "$out = & #{c}"
    end.join("\n")

    run_in_shells nil, <<-EOPS1
#{ vars_to_print(before_vars) }
#{ jc }
#{ vars_to_print(after_vars) }
    EOPS1
  end

  def run_capture_output(command)
    run_in_shells nil, <<-EOPS1
& #{command}
    EOPS1
  end

  def run_in_shells(cmd, ps1)
    Tempfile.open(%w[test .ps1]) do |fd|
      fd.write(ps1)
      fd.close
      IO.popen(["powershell", "-executionpolicy", "Bypass", "-File", fd.path]){|io| io.read }
    end
  end
end
