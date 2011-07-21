require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
include FlexMock::ArgumentTypes

describe "TropoAGItate" do

  before(:all) do
    # These tests are all local unit tests
    FakeWeb.allow_net_connect = false

    # Register where we expect our YAML config file to live
    FakeWeb.register_uri(:get, "http://hosting.tropo.com/49767/www/tropo_agi_config/tropo_agi_config.yml",
                         :body => File.open('tropo_agi_config/tropo_agi_config.yml').read)

    # Register the hosted JSON file
    FakeWeb.register_uri(:get, "http://hosting.tropo.com/49767/www/audio/asterisk_sounds/asterisk_sounds.json",
                         :body => '{"tt-monkeys":"tt-monkeys.gsm"}')

  end

  before(:each) do
    $currentCall   = CurrentCall.new
    $currentApp    = CurrentApp.new
    $incomingCall  = IncomingCall.new
    $destination   = nil
    $caller_id     = nil
    $timeout       = nil
    $network       = nil
    $channel       = nil
    @tropo_agitate = agitate_factory
  end

  it "should create a TropoAGItate object" do
    @tropo_agitate.instance_of?(TropoAGItate).should == true
  end

  describe 'Hash' do
    it 'should symbolize our keys in a hash' do
      h = { 'foo' => 'yes', 'bar' => 'no' }
      h.symbolize_keys!
      h.should == { :foo => 'yes', :bar => 'no' }
    end
  end

  it "should create a properly formatted initial message" do
    agi_uri  = URI.parse @tropo_agitate.tropo_agi_config['agi']['uri_for_local_tests']
    message  = @tropo_agitate.initial_message(agi_uri.host, agi_uri.port, agi_uri.path[1..-1])
    @initial_message = <<-MSG
agi_network: yes
agi_network_script: #{agi_uri.path[1..-1]}
agi_request: agi://#{agi_uri.host}:#{agi_uri.port}#{agi_uri.path}
agi_channel: TROPO/#{$currentCall.sessionId}
agi_language: en
agi_type: TROPO
agi_uniqueid: #{$currentCall.sessionId}
agi_version: tropo-agi-0.1.0
agi_callerid: #{$currentCall.callerID}
agi_calleridname: #{$currentCall.callerName}
agi_callingpres: 0
agi_callingani2: 0
agi_callington: 0
agi_callingtns: 0
agi_dnid: #{$currentCall.calledID}
agi_rdnis: unknown
agi_context: #{agi_uri.path[1..-1]}
agi_extension: s
agi_priority: 1
agi_enhanced: 0.0
agi_accountcode: 0
agi_threadid: #{Thread.current.to_s}
tropo_headers: {\"kermit\":\"green\",\"bigbird\":\"yellow\"}

MSG
    message.should == @initial_message
  end

  it "should parse arguments stripping quotes" do
    result = @tropo_agitate.parse_args('"Hello LSRC!"')
    result[0].should == "Hello LSRC!"

    result = @tropo_agitate.parse_args('"{"prompt":"hi!","timeout":3}"')
    result.should == { "timeout" => 3, "prompt" => "hi!"}

    result = @tropo_agitate.parse_args('"1234","d",""')

    result[0].should == '1234'
    result[1].should == 'd'
    result[3].should == nil
  end

  it "should strip quotes from a string" do
    @tropo_agitate.strip_quotes('"foobar"').should == 'foobar'
  end

  it "should handle commas in non JSON args" do
    command = @tropo_agitate.parse_command('EXEC playback "Hello, LRSC!"')
    command.should == { :action => "exec", :command => "playback", :args => ["Hello, LRSC!"] }
  end

  describe 'parsing the AGI primitive' do
    describe 'ANSWER' do
      it 'should properly parse the AGI input' do
        flexmock($currentCall).should_receive(:answer).once.and_return true
        @tropo_agitate.execute_command('ANSWER').should == "200 result=0\n"
      end
    end

    describe 'ASYNC AGI BREAK' do
      it 'should be an error' do
        expect { @tropo_agitate.execute_command('ASYNC AGI BREAK') }.to raise_error TropoAGItate::NonsenseCommand
      end
    end

    describe 'CHANNEL STATUS' do
      it 'should properly parse the AGI input' do
        @tropo_agitate.execute_command('CHANNEL STATUS').should == "200 result=6\n"
      end

      it 'should be an error if a channel name is specified' do
        expect { @tropo_agitate.execute_command('CHANNEL STATUS Dahdi/22') }.to raise_error TropoAGItate::CommandSoftFail
      end
    end

    describe 'CONTROL STREAM' do
      it 'should properly parse the AGI input' do
        pending "Is this function possible with Tropo?"
      end
    end

    describe 'DATABASE DEL' do
      it 'should be an error' do
        expect { @tropo_agitate.execute_command('DATABASE DEL X Y') }.to raise_error TropoAGItate::NonsenseCommand
      end
    end

    describe 'DATABASE DELTREE' do
      it 'should be an error' do
        expect { @tropo_agitate.execute_command('DATABASE DELTREE X') }.to raise_error TropoAGItate::NonsenseCommand
        expect { @tropo_agitate.execute_command('DATABASE DELTREE X Y') }.to raise_error TropoAGItate::NonsenseCommand
      end
    end

    describe 'DATABASE GET' do
      it 'should be an error' do
        expect { @tropo_agitate.execute_command('DATABASE GET X Y') }.to raise_error TropoAGItate::NonsenseCommand
      end
    end

    describe 'DATABASE PUT' do
      it 'should be an error' do
        expect { @tropo_agitate.execute_command('DATABASE PUT X Y Z') }.to raise_error TropoAGItate::NonsenseCommand
      end
    end

    describe 'EXEC' do
      it 'should properly parse the AGI input' do
        command = @tropo_agitate.parse_command('EXEC playback "Hello LRSC!"')
        command.should == { :action => "exec", :command => "playback", :args => ["Hello LRSC!"] }
      end

      it "should execute the command" do
        result = @tropo_agitate.execute_command('EXEC MeetMe "1234","d",""')
        result.should == "200 result=0\n"

        result = @tropo_agitate.execute_command("EXEC startcallrecording #{{ 'method' => 'POST', 'uri' => 'http://localhost' }.to_json}")
        result.should == "200 result=0\n"

        result = @tropo_agitate.execute_command('EXEC voice "simon"')
        result.should == "200 result=0\n"

        result = @tropo_agitate.execute_command('EXEC recognizer "en-us"')
        result.should == "200 result=0\n"
      end
    end

    describe 'GET DATA' do
      before :each do
        @choice = TropoEvent.new
        @choice.name = 'choice'
        @choice.value = '123'
        @choice_response = "200 result=123\n"

        @timeout = TropoEvent.new
        @timeout.name = 'timeout'
        @timeout_response = "200 result= (timeout)\n"
      end
      it 'should properly parse the AGI input' do
        params = {:timeout => 5, :choices => '[4 DIGITS]', :mode => 'dtmf'}
        flexmock($currentCall).should_receive(:ask).once.with('beep', params).and_return @choice
        @tropo_agitate.execute_command('GET DATA beep 5000 4').should == @choice_response
      end

      it 'should properly signal a timeout condition' do
        flexmock($currentCall).should_receive(:ask).once.and_return @timeout
        @tropo_agitate.execute_command('GET DATA beep 5000 4').should == @timeout_response
      end

      it 'should only accept DTMF input' do
        flexmock($currentCall).should_receive(:ask).once.with('beep', hsh(:mode => 'dtmf')).and_return @choice
        @tropo_agitate.execute_command('GET DATA beep').should == @choice_response
      end

      it 'should default the timeout to 6 seconds' do
        flexmock($currentCall).should_receive(:ask).once.with('beep', hsh(:timeout => 6)).and_return @choice
        @tropo_agitate.execute_command('GET DATA beep').should == @choice_response
      end

      it 'should handle a negative timeout' do
        flexmock($currentCall).should_receive(:ask).once.with('beep', hsh(:timeout => 1000)).and_return @choice
        @tropo_agitate.execute_command('GET DATA beep -1').should == @choice_response
      end

      it 'should default the maximum digits collected to 1024' do
        flexmock($currentCall).should_receive(:ask).once.with('beep', hsh(:choices => '[1024 DIGITS]')).and_return @choice
        @tropo_agitate.execute_command('GET DATA beep').should == @choice_response
      end
    end

    describe 'GET FULL VARIABLE' do
      it 'should be an error' do
        # Implementing this would require implementing a parser for Asterisk's variable expansion logic.
        # NOT going to happen.
        expect { @tropo_agitate.execute_command('GET FULL VARIABLE FOO') }.to raise_error TropoAGItate::NonsenseCommand
      end
    end

    describe 'GET OPTION' do
      before :each do
        @choice = TropoEvent.new
        @choice.name = 'choice'
        @choice.value = '123'
        @choice_response = "200 result=123 endpos=1000\n"

        @timeout = TropoEvent.new
        @timeout.name = 'timeout'
        @timeout_response = "200 result=0 endpos=1000\n"
      end

      it 'should properly parse the AGI input' do
        params = {:timeout => 3, :mode => 'dtmf', :choices => '[1 DIGITS]'}
        flexmock($currentCall).should_receive(:ask).once.with('beep', params).and_return @choice
        @tropo_agitate.execute_command('GET OPTION beep 01234567890#* 3000').should == @choice_response
      end

      it 'should properly handle a timeout response' do
        params = {:timeout => 3, :mode => 'dtmf', :choices => '[1 DIGITS]'}
        flexmock($currentCall).should_receive(:ask).once.with('beep', params).and_return @timeout
        @tropo_agitate.execute_command('GET OPTION beep 01234567890#* 3000').should == @timeout_response
      end

      it 'should default the timeout to 5 seconds' do
        flexmock($currentCall).should_receive(:ask).once.with('beep', hsh(:timeout => 5)).and_return @timeout
        @tropo_agitate.execute_command('GET OPTION beep 01234567890#*').should == @timeout_response
      end
    end

    describe 'GET VARIABLE' do
      it 'should properly parse the AGI input' do
        command = @tropo_agitate.parse_command('GET VARIABLE "myvar"')
        command.should == { :command => "variable", :action => "get", :args => ["myvar"] }
      end
    end

    describe 'GOSUB' do
      it 'should be an error' do
        expect { @tropo_agitate.execute_command('GOSUB testcontext 1 1') }.to raise_error TropoAGItate::NonsenseCommand
        expect { @tropo_agitate.execute_command('GOSUB testcontext 1 1 blah') }.to raise_error TropoAGItate::NonsenseCommand
      end
    end

    describe 'HANGUP' do
      it 'should properly parse the AGI input' do
        command = @tropo_agitate.parse_command('HANGUP')
        command.should == { :action => "hangup" }
      end
    end

    describe 'NOOP' do
      it 'should properly parse the AGI input' do
        @tropo_agitate.execute_command('NOOP').should == "200 result=0\n"
        @tropo_agitate.execute_command('NOOP blah blah blah blah').should == "200 result=0\n"
      end
    end

    describe 'RECEIVE CHAR' do
      it 'should be an error' do
        expect { @tropo_agitate.execute_command('RECEIVE CHAR 5000') }.to raise_error TropoAGItate::NonsenseCommand
      end
    end

    describe 'RECEIVE TEXT' do
      it 'should be an error' do
        expect { @tropo_agitate.execute_command('RECEIVE TEXT 5000') }.to raise_error TropoAGItate::NonsenseCommand
      end
    end

    describe 'RECORD FILE' do
      it 'should properly parse the AGI input' do
        false.should be true
      end
    end

    describe 'SAY ALPHA' do
      it 'should properly parse the AGI input' do
        false.should be true
      end
    end

    describe 'SAY DATE' do
      it 'should properly parse the AGI input' do
        false.should be true
      end
    end

    describe 'SAY DATETIME' do
      it 'should properly parse the AGI input' do
        false.should be true
      end
    end

    describe 'SAY DIGITS' do
      it 'should properly parse the AGI input' do
        false.should be true
      end
    end

    describe 'SAY NUMBER' do
      it 'should properly parse the AGI input' do
        false.should be true
      end
    end

    describe 'SAY PHONETIC' do
      it 'should properly parse the AGI input' do
        false.should be true
      end
    end

    describe 'SAY TIME' do
      it 'should properly parse the AGI input' do
        false.should be true
      end
    end

    describe 'SEND IMAGE' do
      it 'should be an error' do
        expect { @tropo_agitate.execute_command('SEND IMAGE foobar.jpg') }.to raise_error TropoAGItate::NonsenseCommand
      end
    end

    describe 'SEND TEXT' do
      it 'should be an error' do
        expect { @tropo_agitate.execute_command('SEND TEXT TEXT blah_blah_blah') }.to raise_error TropoAGItate::NonsenseCommand
      end
    end

    describe 'SET AUTOHANGUP' do
      it 'should properly parse the AGI input' do
        pending "Does Tropo have a way to do this?"
        # Synopsis
        # Autohangup channel in some time.
        #
        # Description
        # Cause the channel to automatically hangup at time seconds in the future. Of course it can be hungup before then as well. Setting to 0 will cause the autohangup feature to be disabled on this channel.
      end
    end

    describe 'SET CALLERID' do
      it 'should properly parse the AGI input' do
        command = @tropo_agitate.parse_command('SET CALLERID "9095551234"')
        command.should == { :command => "callerid", :action => "set", :args => ["9095551234"] }
      end

      it "should set the callerdID correctly" do
        callerid = "4045551234"
        @tropo_agitate.execute_command("SET VARIABLE CALLERID(num) #{callerid}")
        @tropo_agitate.execute_command("EXEC Dial \"sip:+14045551234\",\"30\",\"\"")
        $currentCall.transferInfo[:options][:callerID].should == callerid
      end
    end

    describe 'SET CONTEXT' do
      it 'should fail softly' do
        expect { @tropo_agitate.execute_command('SET CONTEXT foobar') }.to raise_error TropoAGItate::CommandSoftFail
      end
    end

    describe 'SET EXTENSION' do
      it 'should fail softly' do
        expect { @tropo_agitate.execute_command('SET EXTENSION 1') }.to raise_error TropoAGItate::CommandSoftFail
      end
    end

    describe 'SET MUSIC' do
      it 'should turn music ON' do
        # SET MUSIC ON http://...
        false.should be true
      end

      it 'should turn music OFF' do
        # SET MUSIC OFF
        false.should be true
      end
    end

    describe 'SET PRIORITY' do
      it 'should fail softly' do
        expect { @tropo_agitate.execute_command('SET PRIORITY 1') }.to raise_error TropoAGItate::CommandSoftFail
      end
    end

    describe 'SET VARIABLE do' do
      it 'should properly parse the AGI input' do
        command = @tropo_agitate.parse_command('SET VARIABLE MYVAR "foobar"')
        command.should == { :command => "variable", :action => "set", :args => ["foobar"] }
      end
    end

    describe 'SPEECH ACTIVATE GRAMMAR' do
      it 'should properly parse the AGI input' do
        pending "Leaving this for another day"
      end
    end

    describe 'SPEECH CREATE ENGINE' do
      it 'should fail softly' do
        # Tropo only has one engine
        expect { @tropo_agitate.execute_command('SPEECH CREATE example_engine') }.to raise_error TropoAGItate::CommandSoftFail
      end
    end

    describe 'SPEECH DEACTIVATE GRAMMAR' do
      it 'should properly parse the AGI input' do
        pending "Leaving this for another day"
      end
    end

    describe 'SPEECH DESTROY' do
      it 'should fail softly' do
        # Tropo only has one engine
        expect { @tropo_agitate.execute_command('SPEECH DESTROY') }.to raise_error TropoAGItate::CommandSoftFail
      end
    end

    describe 'SPEECH LOAD GRAMMAR' do
      it 'should properly parse the AGI input' do
        pending "Leaving this for another day"
      end
    end

    describe 'SPEECH RECOGNIZE' do
      it 'should properly parse the AGI input' do
        pending "Leaving this for another day"
      end
    end

    describe 'SPEECH SET' do
      it 'should fail softly' do
        # Tropo only has one engine
        expect { @tropo_agitate.execute_command('SPEECH SET foo bar') }.to raise_error TropoAGItate::CommandSoftFail
      end
    end

    describe 'SPEECH UNLOAD' do
      it 'should properly parse the AGI input' do
        pending "Leaving this for another day"
      end
    end

    describe 'STREAM FILE' do
      it 'should properly parse the AGI input' do
        pending "This is handled specifically in a lot of cases below.  We need a generic test here as well."
      end

      it "should handle the STREAM FILE requests" do
        command = @tropo_agitate.execute_command('STREAM FILE tt-monkeys 1234567890*#')
        command.should == "200 result=57 endpos=1000\n"

        command = @tropo_agitate.execute_command('STREAM FILE tt-monkeys')
        command.should == "200 result=0 endpos=1000\n"

        command = @tropo_agitate.execute_command('STREAM STREAMFILE tt-monkeys 1234567890*#')
        command.should == "200 result=57 endpos=1000\n"
      end

      it "should execute the command as Asterisk-Java would pass" do
        command = @tropo_agitate.execute_command('STREAM FILE "tt-monkeys" "1234567890*#"')
        command.should == "200 result=57 endpos=1000\n"
      end
    end

    describe 'TDD MODE' do
      it 'should be an error' do
        expect { @tropo_agitate.execute_command('TDD MODE on') }.to raise_error TropoAGItate::NonsenseCommand
        expect { @tropo_agitate.execute_command('TDD MODE off') }.to raise_error TropoAGItate::NonsenseCommand
      end
    end

    describe 'VERBOSE' do
      it 'should write a message to the Tropo Application Debugger' do
        flexmock($currentCall).should_receive(:log).once.with('Pay Attention!')
        @tropo_agitate.execute_command('VERBOSE "Pay Attention!"').should == "200 result=1\n"
      end

      it 'should handle escaped double-quotes in log messages' do
        flexmock($currentCall).should_receive(:log).once.with('Pay "Attention!"')
        @tropo_agitate.execute_command('VERBOSE "Pay \"Attention!\""').should == "200 result=1\n"
      end

      it 'should raise ArgumentError if no message is given' do
        expect { @tropo_agitate.execute_command('VERBOSE') }.to raise_error ArgumentError
      end
    end

    describe 'WAIT FOR DIGIT' do
      it 'should properly parse the AGI input' do
        pending "This is handled specifically in a lot of cases below.  We need a generic test here as well."
      end
    end
  end

  describe 'emulating Asterisk dialplan app' do
    describe 'ASK' do
      it 'should parse the input' do
        command = @tropo_agitate.parse_command('EXEC ask "{"prompt":"hi!","timeout":3}"')
        command.should == { :command => "ask", :action => "exec", :args => { "timeout" => 3, "prompt" => "hi!"} }
      end
    end

    describe 'Dial' do
      it 'should properly parse the input' do
        command = @tropo_agitate.parse_command('EXEC Dial "sip:jsgoecke@yahoo.com","",""')
        command.should == { :command => "dial", :action => "exec", :args => ["sip:jsgoecke@yahoo.com", "", ""] }
      end

      it "should set DIALSTATUS after placing a call" do
        dest = "sip:+14045551234"
        @tropo_agitate.execute_command("EXEC Dial \"#{dest}\",\"20\",\"\"")
        command = @tropo_agitate.execute_command('GET VARIABLE DIALSTATUS')
        command.should == "200 result=1 (ANSWER)\n"
        $currentCall.transferInfo[:destinations].should == [dest]
      end

      it "should set the dial timeout correctly" do
        timeout = 45
        @tropo_agitate.execute_command("EXEC Dial \"sip:+14045551234\",\"#{timeout}\",\"\"")
        $currentCall.transferInfo[:options][:timeout].should == timeout
      end
    end

    describe 'AMD' do
      it 'should properly parse the input' do
        command = @tropo_agitate.parse_command('EXEC AMD')
        command.should == { :command => "amd", :action => "exec" }
      end

      it "should properly detect an answering machine" do
        flexmock($currentCall).should_receive(:record).and_return do |*args|
          # Simulate a long recording, indicating that silence is not received for more than 4 seconds
          sleep 5
        end

        @tropo_agitate.execute_command("EXEC AMD")
        amdstatus = @tropo_agitate.execute_command('GET VARIABLE AMDSTATUS')
        amdcause  = @tropo_agitate.execute_command('GET VARIABLE AMDCAUSE')
        amdstatus.should == "200 result=1 (MACHINE)\n"
        amdcause.should  == "200 result=1 (TOOLONG-5)\n"
      end

      it "should properly detect a human" do
        @tropo_agitate.execute_command("EXEC AMD")
        amdstatus = @tropo_agitate.execute_command('GET VARIABLE AMDSTATUS')
        amdcause  = @tropo_agitate.execute_command('GET VARIABLE AMDCAUSE')
        amdstatus.should == "200 result=1 (HUMAN)\n"
        amdcause.should  == "200 result=1 (HUMAN-1-1)\n"
      end
    end

    describe 'MeetMe' do
      it 'should properly parse the input' do
        command = @tropo_agitate.parse_command('EXEC MeetMe "1234","d",""')
        command.should == { :command => "meetme", :action => "exec", :args => ["1234", "d", ""] }
      end
    end

    describe 'Monitor' do
      it 'should properly parse the input' do
        command = @tropo_agitate.parse_command('EXEC monitor "http://localhost"')
        command.should == { :command => "monitor", :action => "exec", :args => [ 'http://localhost' ] }
      end
    end

    describe 'MixMonitor' do
      it 'should properly parse the input' do
        command = @tropo_agitate.parse_command('EXEC mixmonitor "{"method":"POST","uri":"http://localhost"}"')
        command.should == { :command => "mixmonitor", :action => "exec", :args => { 'method' => 'POST', 'uri' => 'http://localhost' } }
      end
    end

    describe 'Playback' do
      it "should execute the command as Asterisk-Java would pass" do
        command = @tropo_agitate.execute_command('EXEC "playback" "tt-monkeys"')
        command.should == "200 result=0\n"
      end
    end
  end

  describe 'Tropo-specific dialplan application' do
    describe 'StartCallRecording' do
      it 'should properly parse the input' do
        command = @tropo_agitate.parse_command('EXEC startcallrecording "{"method":"POST","uri":"http://localhost"}"')
        command.should == { :command => "startcallrecording", :action => "exec", :args => { 'method' => 'POST', 'uri' => 'http://localhost' } }
      end
    end
  end

  describe 'Tropo compatibility with Asterisk behavior' do
    it "should handle magic channel variables properly" do
      number = "9095551234"
      name = "John Denver"

      command = @tropo_agitate.execute_command("SET CALLERID \"<#{number}>\"")
      command.should == "200 result=0\n"
      command = @tropo_agitate.execute_command('GET VARIABLE CALLERID(num)')
      command.should == "200 result=1 (#{number})\n"

      command = @tropo_agitate.execute_command("SET VARIABLE CALLERIDNAME \"#{name}\"")
      command.should == "200 result=0\n"
      command = @tropo_agitate.execute_command('GET VARIABLE "CALLERIDNAME"')
      command.should == "200 result=1 (John Denver)\n"
      command = @tropo_agitate.execute_command('GET VARIABLE "CALLERID(name)"')
      command.should == "200 result=1 (John Denver)\n"

      command = @tropo_agitate.execute_command('GET VARIABLE "CALLERID(all)"')
      command.should == "200 result=1 (\"#{name}\" <#{number}>)\n"

      command = @tropo_agitate.execute_command('SET VARIABLE FOOBAR "green"')
      command.should == "200 result=0\n"
      command = @tropo_agitate.execute_command('GET VARIABLE "FOOBAR"')
      command.should == "200 result=1 (green)\n"
    end
  end

  it "should return the account data from a directory lookup on Windows" do
    TropoAGItate.new($currentCall, CurrentApp.new(49767)).fetch_account_data[1].should == '49767'
  end

  it "should return the account data from a directory lookup on Linux" do
    FakeWeb.register_uri(:get, "http://hosting.tropo.com/49768/www/tropo_agi_config/tropo_agi_config.yml",
                         :body => File.open('tropo_agi_config/tropo_agi_config.yml').read)
    TropoAGItate.new($currentCall, CurrentApp.new(49768)).fetch_account_data[1].should == '49768'
  end

  it "should execute a read" do
    command = @tropo_agitate.execute_command('EXEC READ pin,tt monkeys,5,,3,10')
    command.should == "200 result=0\n"
  end

  it 'should properly dial an outbound call when invoked via REST' do
    # Simulate parameters passed as query string variables
    $currentCall = nil
    $destination = '14045556789'
    $caller_id   = '14155551234'
    $timeout     = '47'

    options = {:callerID => $caller_id,
               :timeout => $timeout.to_i,
               :channel => 'voice',
               :network => 'SMS'}

    # Test the origination
    response = TropoEvent.new
    response.name = 'answer'
    flexmock(self).should_receive(:call).with("tel:+#{$destination}", options).and_return response
    @tropo_agitate = agitate_factory
  end

  it 'should send a "failed" call when dial results in an error' do
    # Simulate parameters passed as query string variables
    $currentCall = nil
    $destination = 'XXX'
    $caller_id   = '14155551234'
    $timeout     = '47'

    options = {:callerID => $caller_id,
               :timeout => $timeout.to_i,
               :channel => 'voice',
               :network => 'SMS'}

    # Test the origination
    response = TropoEvent.new
    response.name = 'error'
    flexmock(self).should_receive(:call).with("tel:+#{$destination}", options).and_return response
    @tropo_agitate = agitate_factory

    agi_environment = @tropo_agitate.initial_message('127.0.0.1', 1, 'example').split("\n")
    agi_environment.grep(/agi_extension/)[0].match(/^agi_extension: (.*)$/)[1].should == 'failed'

    @tropo_agitate.execute_command('GET VARIABLE REASON').should == "200 result=1 (8)\n"
  end
end
