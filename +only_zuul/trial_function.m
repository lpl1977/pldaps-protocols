function p = trial_function(p,state)
%  PLDAPS trial function for set task
%
%  p = only_zuul.trial_function(p,state)

%
%  Call default trial function for general state dependent steps not
%  defined here
%
pldapsDefaultTrialFunction(p,state);

%
%  Custom defined state dependent steps
%
switch state
    
    case p.trial.pldaps.trialStates.trialSetup
        %  Trial Setup, for example starting up Datapixx ADC and allocating
        %  memory
        
        %  This is where we would perform any steps that needed to be done
        %  before a trial is started, for example preparing stimuli
        %  parameters
        
        %  Confirm joystick is attached; if not, then stop trial and pause
        %  protocol
        if(~joystick.connected)
            disp('Warning:  joystick disconnected.  Plug it in, I will wait...');
            p.trial.pldaps.pause.type = 1;
            p.trial.pldaps.quit = 1;
        end
        
        %  Set subject specific parameters / actions
        feval(str2func(strcat('only_zuul.',p.trial.session.subject)),p);
        
        %  Initialize or update trial indexing
        if(p.trial.pldaps.iTrial==1)
            p.trial.indexing.current_trial = 1;
            p.trial.indexing.next_trial = 2;
            p.trial.indexing.total_completed = 0;
            p.trial.indexing.repeats = 0;
        else
            p.trial.indexing = p.data{p.trial.pldaps.iTrial-1}.indexing;
            p.trial.indexing.current_trial = p.trial.indexing.next_trial;
        end
        
        %  Conditions from cell array
        p.trial.condition = p.conditions{p.trial.indexing.current_trial};
        
        %  Initialize trial state variables
        p.trial.state_variables = only_zuul.state_variables(p.trial.condition);
        
%         %  Initialize performance
%         if(p.trial.pldaps.iTrial==1)
%             nlum = length(p.trial.specs.features.log10C);
%             p.trial.specs.performance.total = only_zuul.performance(nlum+1);
%             p.trial.specs.performance.mask = only_zuul.performance(nlum+1);
%             p.trial.specs.performance.set = only_zuul.performance(nlum);
%             p.trial.specs.performance.notset = only_zuul.performance(1);
%         else
%             p.trial.specs.performance = p.data{p.trial.pldaps.iTrial-1}.task.performance;
%         end
        
        %  Initialize random symbol position order
        p.trial.specs.features.symbol.position_order = randperm(3)+3*(unidrnd(2)-1);
        
        %  Prepare for symbol masks (even if we don't use them, take same
        %  time every trial).
        p.trial.specs.features.symbol.rng_seed = rng;
        diameter = p.trial.specs.features.symbol.outer_diameter;
        colors = p.trial.specs.features.symbol.colors;
        mix = ones(1,length(p.trial.specs.features.symbol.colors))/length(p.trial.specs.features.symbol.colors);
        %p.trial.specs.features.symbol.masks = only_zuul.symbol_masks(diameter,colors,mix,p.trial.specs.features.symbol.rng_seed);
        
        only_zuul.symbol_masks.init(diameter,colors,mix,p.trial.specs.features.symbol.rng_seed);
        
        %  Setup for noise annulus
        p.trial.specs.features.annulus.rng_seed = rng;
        annulus_dimensions = [p.trial.specs.features.annulus.outer_diameter p.trial.specs.features.annulus.inner_diameter];
        response_cue_dimensions = [p.trial.specs.features.response_cue.diameter+2*p.trial.specs.features.response_cue.linewidth p.trial.specs.features.response_cue.diameter];
        only_zuul.noise_ring.init(annulus_dimensions,response_cue_dimensions,p.trial.specs.features.annulus.rng_seed);
        
        %  Print trial information to screen
        
        fprintf('START TRIAL ATTEMPT %d (%d total trials of %d completed, %d remain):\n',p.trial.pldaps.iTrial,p.trial.indexing.total_completed,p.trial.specs.constants.maxTrials,p.trial.specs.constants.maxTrials-p.trial.indexing.total_completed);
        fprintf('\tTrial %d of %d for block %d of %d.\n',p.trial.condition.trial_number,p.trial.specs.constants.TrialsPerBlock,p.trial.condition.block_number,p.trial.specs.constants.maxBlocks);
        fprintf('\tThis is a %s %s trial with log contrast %0.3f.\n',upper(p.trial.condition.sequence_type),upper(p.trial.condition.trial_type),p.trial.condition.log10C);
        
    case p.trial.pldaps.trialStates.trialCleanUpandSave
        %  Clean Up and Save, post trial management
        
        %  If we are still in the experiment, then update indexing and deal
        %  with errors and aborts, etc.
        
        if(p.trial.pldaps.quit == 0)
            
            %  Update performance
            %         p.trial.specs.performance.total = only_zuul.performance.update(p.trial.specs.performance.total,p.trial.outcome,p.trial.condition);
            %         p.trial.specs.performance.(p.trial.condition.sequence_type) = only_zuul.performance.update(p.trial.specs.performance.(p.trial.condition.sequence_type),p.trial.outcome,p.trial.condition);
            %
            %
            %  Update trial indexing
            %
            
            %  Depending on training flags, shuffle aborts and errors.
            
            if(p.trial.outcome.completed && (p.trial.outcome.correct || ~p.trial.training_flags.repeat_errors))
                p.trial.indexing.next_trial = p.trial.indexing.current_trial+1;
                p.trial.indexing.total_completed = p.trial.indexing.total_completed + 1;
            else
                if(p.trial.outcome.completed && ~p.trial.outcome.correct)
                    p.trial.indexing.repeats = p.trial.indexing.repeats+1;
                end
                p.trial.indexing.next_trial = p.trial.indexing.current_trial;
                p.conditions{end+1} = p.conditions{end};
                if((p.trial.training_flags.shuffle_aborts && ~p.trial.outcome.completed) || (p.trial.outcome.completed && p.trial.training_flags.shuffle_errors))
                    indx = p.trial.indexing.current_trial:p.trial.indexing.current_trial + p.trial.specs.constants.TrialsPerBlock-p.trial.condition.trial_number;
                    fprintf('\tReshuffling trials %d through %d (within block trial %d through %d)\n\n',indx(1),indx(end),p.trial.condition.trial_number,p.trial.specs.constants.TrialsPerBlock);
                    temp = p.conditions(indx);
                    p.conditions(indx) = Shuffle(temp);
                    for i = 1:length(indx)
                        p.conditions{indx(i)}.trial_number = temp{i}.trial_number;
                    end
                end
            end
            
            %  Check if we have completed conditions; if so, we're finished.
            
            if(p.trial.indexing.total_completed == p.trial.specs.constants.maxTrials + p.trial.indexing.repeats)
                p.trial.pldaps.quit=2;
            end
        else
            
            %  Trial was interrupted by user (paused or quit)            
            p.trial.outcome = interrupted_trial;            
        end
        
        %  Clean up state variables
        p.trial = rmfield(p.trial,'state_variables');
        
        
        %  Display performance
        %       only_zuul.performance.print_summary_performance(p.trial.specs.performance); %,p.trial.specs.features.log10C);
        
        %  Display aborts
        %        only_zuul.performance.print_summary_trial_aborts(p.trial.specs.performance);
        
        %
        %         fprintf('MASK current performance:\n');
        %         only_zuul.performance.print_performance(p.trial.specs.performance.mask,p.trial.specs.features.log10C);
        %
        %         fprintf('SET current performance:\n');
        %         only_zuul.performance.print_performance(p.trial.specs.performance.set,p.trial.specs.features.log10C);
        %
        %         fprintf('NOTSET current performance:\n');
        %         only_zuul.performance.print_performance(p.trial.specs.performance.notset,-Inf);
        
        %         completed = double(p.trial.specs.performance.completed); attempted
        %         = double(p.trial.specs.performance.attempted); correct =
        %         double(p.trial.specs.performance.correct);
        %
        %         fixation_breaks =
        %         double(p.trial.specs.performance.fixation_break);
        %         failed_to_initiate =
        %         double(p.trial.specs.performance.failed_to_initiate);
        %         joystick_warning_elapsed =
        %         double(p.trial.specs.performance.joystick_warning_elapsed);
        %         eye_warning_elapsed =
        %         double(p.trial.specs.performance.eye_warning_elapsed);
        %         early_releases = double(p.trial.specs.performance.early_release);
        %         early_presses = double(p.trial.specs.performance.early_press);
        %         release_drift_errors =
        %         double(p.trial.specs.performance.release_drift_error);
        %         press_drift_errors =
        %         double(p.trial.specs.performance.press_drift_error); misses =
        %         double(p.trial.specs.performance.miss);
        %
        %         fprintf('Current performance:\n'); fprintf('\tCompleted:
        %         %d of %d (%0.3f)\n',completed,attempted,completed/attempted);
        %         fprintf('\tCorrectly completed:  %d of %d
        %         (%0.3f)\n',correct,completed,correct/completed); fprintf('\n');
        %
        %         for i=1:length(p.trial.specs.features.log10C)
        %             fprintf('         R (%5.2f):  %4d R %4d P %4d T, %5.2f
        %             correct | %5.2f
        %             R\n',p.trial.specs.features.log10C(i),p.trial.specs.performance.matrix(i,:),p.trial.specs.performance.matrix(i,1)/p.trial.specs.performance.matrix(i,3),p.trial.specs.performance.matrix(i,1)/p.trial.specs.performance.matrix(i,3));
        %         end fprintf('         P (%5.2f):  %4d R %4d P %4d T, %5.2f
        %         correct | %5.2f
        %         R\n',-Inf,p.trial.specs.performance.matrix(end,:),p.trial.specs.performance.matrix(end,2)/p.trial.specs.performance.matrix(end,3),p.trial.specs.performance.matrix(end,1)/p.trial.specs.performance.matrix(end,3));
        %         fprintf('\n');
        %
        %         fprintf('Trial aborts (%d of %d
        %         trials):\n',attempted-completed,attempted); fprintf('\tFixation
        %         breaks:          %3d\n',fixation_breaks); fprintf('\tFailed to
        %         initiate:       %3d\n',failed_to_initiate); fprintf('\tJoystick
        %         warning elapsed: %3d\n',joystick_warning_elapsed); fprintf('\tEye
        %         warning elapsed:      %3d\n',eye_warning_elapsed);
        %         fprintf('\tEarly releases:           %3d\n',early_releases);
        %         fprintf('\tEarly presses:            %3d\n',early_presses);
        %         fprintf('\tRelease drift errors:
        %         %3d\n',release_drift_errors); fprintf('\tPress drift errors:
        %         %3d\n',press_drift_errors); fprintf('\tMisses:
        %         %3d\n',misses); fprintf('\n');
                
    case p.trial.pldaps.trialStates.frameDraw
        %  Final image has been calculated and will now be drawn
        
        %  Got nothing here on my end
        
    case p.trial.pldaps.trialStates.frameUpdate
        %  Frame Update is called once after the last frame is done (or
        %  even before).  Get current eyepostion, curser position,
        %  keypresses, joystick position, etc.
        
        %  Get current fixation status
        check_fixation_status;
        
        %  Get current joystick status
        check_joystick_status;
        
    case p.trial.pldaps.trialStates.framePrepareDrawing
        %  Frame PrepareDrawing is where you can prepare all drawing and
        %  task state control.
        
        %
        %  Check trial time first; end trial if exceeds maximum
        %
        
        if(p.trial.ttime > p.trial.pldaps.maxTrialLength-p.trial.specs.constants.minTrialTime)
            fprintf('\t%s did not initiate trial within %0.3f sec.\n',p.trial.session.subject,p.trial.pldaps.maxTrialLength-60);            
            p.trial.outcome = aborted_trial('failed to initiate');            
            fprintf('END TRIAL %d.\n\n',p.trial.pldaps.iTrial);
            p.trial.flagNextTrial = true;
        end
        
        %
        %  Drawing done in every frame
        %
        
        %  Display joystick status to screen
        display_joystick_status;
        
        %  Display fixation window
        display_fixation_window;
        
        %
        %  Control trial events based on trial state
        %
        
        switch p.trial.state_variables.trial_state
            
            case 'start'
                
                %  STATE:  start
                
                %  If monkey has joystick released then go to engage state.
                %  Otherwise go to joystick warning.
                
                if(~p.trial.state_variables.joystick_released)
                    %  Monkey does not have joystick released.
                    fprintf('\t%s started trial without joystick released; go to joystick warning.\n',p.trial.session.subject);
                    p.trial.state_variables.wait_for_release = true;
                    p.trial.state_variables.trial_state = 'joystick_warning';
                else
                    %  Monkey has joystick released.
                    fprintf('\t%s started trial with joystick released; go to engage.\n',p.trial.session.subject);
                    p.trial.state_variables.trial_state = 'engage';
                end
                
                %  Show fixation cue
                ShowFixationCue;
                
            case 'engage'
                
                %  STATE:  engage
                
                %  Start trial once monkey has joystick engaged and is
                %  fixating.
                
                if(isnan(p.trial.specs.timing.engage.start_time))
                    
                    %  This is our first pass through on this trial; start
                    %  our timers and print some feedback to screen.
                    p.trial.specs.timing.engage.start_time = GetSecs;
                    p.trial.specs.timing.engage.cue_start_time = GetSecs;
                    
                    %  Show fixation cue
                    ShowFixationCue;
                    
                    fprintf('ENGAGE state\n');
                    
                    %  If the monkey is not currently fixating then we're
                    %  going to have to wait for him to fixate.
                    if(~p.trial.state_variables.fixating)
                        fprintf('\t%s must fixate before we may proceed.\n',p.trial.session.subject);
                        p.trial.state_variables.wait_for_fixation = true;
                    else
                        p.trial.state_variables.wait_for_fixation = false;
                    end
                    
                    %  If the monkey does not currently have the joystick
                    %  engaged then we are going to have to wait for him to
                    %  engage.
                    if(~p.trial.state_variables.joystick_engaged)
                        fprintf('\t%s must engage joystick before we may proceed.\n',p.trial.session.subject);
                        p.trial.state_variables.wait_for_engage = true;
                    else
                        p.trial.state_variables.wait_for_engage = false;
                    end
                else
                    
                    %  We are still in the engage state.  We will continue
                    %  checking the joystick and fixation and will blinked
                    %  the fixation cue as long as the monkey has both not
                    %  engaged the joystick and fixated.
                    
                    if(p.trial.state_variables.joystick_engaged && p.trial.state_variables.fixating)
                        
                        %  The monkey has both joystick engaged and is
                        %  fixating.  Print some feedback, reset the timing
                        %  variables, and go on to the delay state.
                        fprintf('\t%s engaged joystick and is fixating after %0.3f sec.\n',p.trial.session.subject,GetSecs-p.trial.specs.timing.engage.start_time);
                        p.trial.specs.timing.engage.start_time = NaN;
                        p.trial.specs.timing.engage.cue_start_time = NaN;
                        p.trial.state_variables.trial_state = 'delay';
                        
                        %  Show fixation cue
                        ShowFixationCue;
                        
                    elseif(p.trial.state_variables.joystick_pressed || p.trial.state_variables.joystick_press_buffer)
                        
                        %  The monkey overshot the engage region.
                        fprintf('\t%s pressed the joystick after %0.3f sec; go to joystick warning.\n',p.trial.session.subject,GetSecs-p.trial.specs.timing.engage.start_time);
                        p.trial.specs.timing.engage.start_time = NaN;
                        p.trial.specs.timing.engage.cue_start_time = NaN;
                        p.trial.state_variables.trial_state = 'joystick_warning';
                        
                        %  Show fixation cue
                        ShowFixationCue;
                        
                    elseif(p.trial.specs.timing.engage.cue_start_time > GetSecs - p.trial.specs.timing.engage.cue_display_time)
                        
                        %  We're not yet in the blink so show the fixation
                        %  cue regarless.
                        ShowFixationCue;
                        
                    elseif(p.trial.specs.timing.engage.cue_start_time <= GetSecs - (p.trial.specs.timing.engage.cue_display_time + p.trial.specs.timing.engage.cue_extinguish_time))
                        
                        %  We've exceeded the duration of the blink, so
                        %  reset the cue start time.
                        p.trial.specs.timing.engage.cue_start_time = GetSecs;
                        
                        %  Show the fixation cue regardless
                        ShowFixationCue;
                    end
                end
                
            case 'delay'
                
                %  STATE:  delay
                
                %  Monkey enters the state for the first time with the
                %  joystick engaged and fixating.  Continue to show him the
                %  fixation cue as long as this is the case and we have not
                %  yet reached the end of the delay period.
                
                ShowFixationCue;
                if(isnan(p.trial.specs.timing.delay.start_time))
                    p.trial.specs.timing.delay.start_time = GetSecs;
                    fprintf('DELAY state for %0.3f sec.\n',p.trial.specs.timing.delay.duration);                    
                elseif(p.trial.specs.timing.delay.start_time > GetSecs - p.trial.specs.timing.delay.duration)
                    
                    %  We're still in the delay period.  As long as he
                    %  continues to engage and fixate, show him the
                    %  fixation cue.  If he releases or breaks fixation
                    %  during this period, give him a timeout.  If he
                    %  pushes the joystick too far then give him a joystick
                    %  warning.
                    
                    if(~p.trial.state_variables.joystick_engaged)
                        %  Monkey released or pressed joystick early.                        
                        if(p.trial.state_variables.joystick_released || p.trial.state_variables.joystick_release_buffer)
                            fprintf('\t%s released joystick at %0.3f sec; go to engage.\n',...'delay'
                                p.trial.session.subject,GetSecs-p.trial.specs.timing.delay.start_time);
                            p.trial.state_variables.trial_state = 'engage';
                        else
                            fprintf('\t%s pressed joystick at %0.3f sec, give him a joystick warning.\n',...
                                p.trial.session.subject,GetSecs-p.trial.specs.timing.delay.start_time);
                            p.trial.state_variables.trial_state = 'joystick_warning';
                        end
                        p.trial.specs.timing.delay.start_time = NaN;
                    elseif(~p.trial.state_variables.fixating)
                        %  Monkey broke fixation.
                        fprintf('\t%s broke fixation after %0.3f sec; give him an eye warning.\n',...
                            p.trial.session.subject,GetSecs-p.trial.specs.timing.delay.start_time);
                        p.trial.specs.timing.delay.start_time = NaN;
                        p.trial.state_variables.trial_state = 'eye_warning';
                    end                    
                else
                    %  Monkey has successfully held the joystick engaged
                    %  and fixated to the end of the duration.                    
                    fprintf('\t%s successfully held joystick engaged and remained fixating.\n',p.trial.session.subject);
                    p.trial.state_variables.trial_state = 'symbol';
                    p.trial.specs.timing.delay.start_time = NaN;
                end
                
            case 'joystick_warning'
                
                %  STATE:  joystick_warning
                
                %  Monkey enters this state if he has pushed the joystick
                %  too far.  Exit joystick warning when he gets the
                %  joystick into the appropriate range (either release or
                %  engage).
                
                %  Fixation cue will be red
                ShowFixationCue;
                
                if(isnan(p.trial.specs.timing.joystick_warning.start_time))
                    
                    %  This is our first pass through on this trial; start
                    %  our timers and print some feedback to screen.
                    p.trial.specs.timing.joystick_warning.start_time = GetSecs;
                    fprintf('JOYSTICK WARNING started for %0.3f sec.\n',p.trial.specs.timing.joystick_warning.duration);
                    
                    %  Play the joystick warning until he returns joystick
                    %  to appropriate position
                    pds.audio.play(p,'joystick_warning',Inf);
                    
                elseif(p.trial.specs.timing.joystick_warning.start_time > GetSecs - p.trial.specs.timing.joystick_warning.duration)
                    
                    
                    %  We are still in the joystick warning state.  We will
                    %  continue the joystick warning as long as the monkey
                    %  has not moved the joystick back into the appropriate
                    %  range.
                    
                    if(p.trial.state_variables.wait_for_release && p.trial.state_variables.joystick_released)
                        p.trial.state_variables.wait_for_release = false;
                        
                        %  Monkey released joystick
                        fprintf('\t%s released joystick after %0.3f sec.\n',p.trial.session.subject,GetSecs-p.trial.specs.timing.joystick_warning.start_time);
                        p.trial.specs.timing.joystick_warning.start_time = NaN;
                        p.trial.state_variables.trial_state = 'engage';
                        
                        %  Stop the joystick warning tone
                        pds.audio.stop(p,'joystick_warning');
                        
                        
                    elseif(~p.trial.state_variables.wait_for_release)
                        if(p.trial.state_variables.joystick_engaged)
                            
                            %  Monkey has joystick engaged
                            fprintf('\t%s re-engaged joystick after %0.3f sec.\n',p.trial.session.subject,GetSecs-p.trial.specs.timing.joystick_warning.start_time);
                            p.trial.specs.timing.joystick_warning.start_time = NaN;
                            p.trial.state_variables.trial_state = 'delay';
                            
                            %  Stop the joystick warning tone
                            pds.audio.stop(p,'joystick_warning');
                        elseif(p.trial.state_variables.joystick_released || p.trial.state_variables.joystick_release_buffer)
                            
                            %  Monkey has somehow managed to pass back
                            %  through the engaged state
                            fprintf('\t%s released joystick after %0.3f sec.\n',p.trial.session.subject,GetSecs-p.trial.specs.timing.joystick_warning.start_time);
                            p.trial.specs.timing.joystick_warning.start_time = NaN;
                            p.trial.state_variables.trial_state = 'start';
                            
                            %  Stop the joystick warning tone
                            pds.audio.stop(p,'joystick_warning');
                        end
                    end
                    
                else
                    %  Monkey has failed to re-engage within the joystick
                    %  warning duration
                    
                    %  Stop the joystick warning tone
                    pds.audio.stop(p,'joystick_warning');
                    
                    fprintf('\t%s elapsed his joystick warning interval.\nEND TRIAL %d.\n\n',p.trial.session.subject,p.trial.pldaps.iTrial);                    

                    p.trial.outcome = aborted_trial('joystick warning elapsed');
                    p.trial.specs.timing.joystick_warning.start_time = NaN;                    
                    p.trial.flagNextTrial = true;                    
                end
                
            case 'eye_warning'
                
                %  STATE:  eye_warning
                
                %  Monkey enters this state if he has broken fixation
                %  during the delay period.  Exit eye warning when he is
                %  fixating and has the joystick engaged.  If he releases
                %  go back to engage and if he presses go back to warning.
                %  While in the eye warning we will blink the fixation cue
                %  at him as in the engage state.
                
                
                if(isnan(p.trial.specs.timing.eye_warning.start_time))
                    
                    %  This is our first pass through on this trial; start
                    %  our timers and print some feedback to screen.
                    p.trial.specs.timing.eye_warning.start_time = GetSecs;
                    p.trial.specs.timing.eye_warning.cue_start_time = GetSecs;
                    fprintf('EYE WARNING started for %0.3f sec.\n',p.trial.specs.timing.eye_warning.duration);
                    
                    %  Play the eye warning until he returns to fixation
                    pds.audio.play(p,'eye_warning',Inf);
                    
                    %  Show fixation cue
                    ShowFixationCue;                    
                elseif(p.trial.specs.timing.eye_warning.start_time <= GetSecs - p.trial.specs.timing.eye_warning.duration)
                    
                    %  Monkey has failed to fixate during the warning
                    %  duration
                    
                    %  Stop the eye warning tone
                    pds.audio.stop(p,'eye_warning');
                    
                    fprintf('\t%s elapsed his eye warning interval.\nEND TRIAL %d.\n\n',p.trial.session.subject,p.trial.pldaps.iTrial);
                    
                    p.trial.outcome = aborted_trial('eye warning elapsed');                    
                    p.trial.specs.timing.eye_warning.start_time = NaN;
                    p.trial.specs.timing.eye_warning.cue_start_time = GetSecs;                    
                    p.trial.flagNextTrial = true;                    
                else
                    
                    %  We are still in the eye warning state.  We will
                    %  continue to check fixation and blink the fixation
                    %  cue as long as the monkey has not returned to
                    %  fixation and we haven't elapsed the maximum warning
                    %  time.
                    
                    if(p.trial.state_variables.fixating)
                        
                        %  The monkey has returned to fi_xation!  Reset the
                        %  timing variables and go back to the delay state.
                        fprintf('\t%s fixated after %0.3f sec.\n',p.trial.session.subject,GetSecs-p.trial.specs.timing.eye_warning.start_time);
                        p.trial.specs.timing.eye_warning.start_time = NaN;
                        p.trial.specs.timing.eye_warning.cue_start_time = NaN;
                        p.trial.state_variables.trial_state = 'delay';
                        
                        %  Stop the eye warning tone
                        pds.audio.stop(p,'eye_warning');
                        
                        %  Show fixation cue
                        ShowFixationCue;
                        
                    elseif(p.trial.state_variables.joystick_pressed || p.trial.state_variables.joystick_press_buffer)
                        
                        %  The monkey overshot the engage region.
                        fprintf('\t%s pressed the joystick after %0.3f sec; go to joystick warning.\n',p.trial.session.subject,GetSecs-p.trial.specs.timing.eye_warning.start_time);
                        p.trial.specs.timing.eye_warning.start_time = NaN;
                        p.trial.specs.timing.eye_warning.cue_start_time = NaN;
                        p.trial.state_variables.trial_state = 'joystick_warning';
                        
                        %  Stop the eye warning tone
                        pds.audio.stop(p,'eye_warning');
                        
                        %  Show fixation cue
                        ShowFixationCue;
                        
                    elseif(p.trial.state_variables.joystick_released || p.trial.state_variables.joystick_release_buffer)
                        
                        %  The monkey released the joystick.
                        fprintf('\t%s released the joystick after %0.3f sec; go to engage.\n',p.trial.session.subject,GetSecs-p.trial.specs.timing.eye_warning.start_time);
                        p.trial.specs.timing.eye_warning.start_time = NaN;
                        p.trial.specs.timing.eye_warning.cue_start_time = NaN;
                        p.trial.state_variables.trial_state = 'engage';
                        
                        %  Stop the eye warning tone
                        pds.audio.stop(p,'eye_warning');
                        
                        %  Show fixation cue
                        ShowFixationCue;
                        
                        
                    elseif(p.trial.specs.timing.eye_warning.cue_start_time > GetSecs - p.trial.specs.timing.eye_warning.cue_display_time)
                        
                        %  We're not yet in the blink so show the fixation
                        %  cue regarless.
                        ShowFixationCue;
                        
                    elseif(p.trial.specs.timing.eye_warning.cue_start_time <= GetSecs - (p.trial.specs.timing.eye_warning.cue_display_time + p.trial.specs.timing.eye_warning.cue_extinguish_time))
                        
                        %  We've exceeded the duration of the blink, so
                        %  reset the cue start time.
                        p.trial.specs.timing.eye_warning.cue_start_time = GetSecs;
                        
                        %  Show the fixation cue regardless
                        ShowFixationCue;
                    end
                end
                
            case 'symbol'
                
                %  STATE:  symbol
                
                %  Monkey enters the state for the first time with the
                %  joystick engaged and fixating.  Continue to show him the
                %  fixation cue as long as this is the case and we have not
                %  yet reached the end of the symbol presentation period.
                %
                %  Monkey should remain fixating with joystick engaged for
                %  entire duration of this period
                
                ShowFixationCue;
                
                if(isnan(p.trial.specs.timing.symbol.start_time))
                    p.trial.specs.timing.symbol.start_time = GetSecs;
                    
                    if(p.trial.state_variables.mask_trial)
                        fprintf('SYMBOL MASK, %d of 3 for %0.3f sec.\n',p.trial.state_variables.current_symbol,p.trial.specs.timing.symbol.display_time);
                        ShowSymbolMask;
                    else
                        fprintf('SYMBOL %s, %d of 3 for %0.3f sec.\n',p.trial.condition.symbol_features(p.trial.state_variables.current_symbol).name,p.trial.state_variables.current_symbol,p.trial.specs.timing.symbol.display_time);
                        ShowSymbol;
                    end
                    
                elseif(~p.trial.state_variables.joystick_engaged)
                    %  Monkey released or pressed joystick early.
                    
                    if(p.trial.state_variables.joystick_released || p.trial.state_variables.joystick_release_buffer)
                        fprintf('\t%s released joystick at %0.3f sec, give him a timeout.\n',...
                            p.trial.session.subject,GetSecs-p.trial.specs.timing.symbol.start_time);
                        p.trial.outcome = aborted_trial('early release');
                    else
                        fprintf('\t%s pressed joystick at %0.3f sec, give him a timeout.\n',...
                            p.trial.session.subject,GetSecs-p.trial.specs.timing.symbol.start_time);
                        p.trial.outcome = aborted_trial('early press');
                    end
                    p.trial.state_variables.trial_state = 'timeout';
                    p.trial.specs.timing.symbol.start_time = NaN;
                elseif(~p.trial.state_variables.fixating)
                    %  Monkey broke fixation.
                    
                    fprintf('\t%s broke fixation after %0.3f sec; give him a timeout.\n',...
                        p.trial.session.subject,GetSecs-p.trial.specs.timing.delay.start_time);
                    p.trial.outcome = aborted_trial('fixation break');   
                    p.trial.specs.timing.symbol.start_time = NaN;
                    p.trial.state_variables.trial_state = 'timeout';
                elseif(p.trial.specs.timing.symbol.start_time <= GetSecs - (p.trial.specs.timing.symbol.display_time + p.trial.specs.timing.symbol.interval))
                    %  We have reached the end of the current symbol, so
                    %  update
                    if(p.trial.specs.timing.symbol.interval==0 || p.trial.training_flags.continue_symbols)
                        if(p.trial.state_variables.mask_trial)
                            ShowSymbolMask;
                        else
                            ShowSymbol;
                        end
                    end
                    p.trial.specs.timing.symbol.start_time = NaN;
                    if(p.trial.state_variables.current_symbol==3)
                        p.trial.state_variables.trial_state = 'response_cue';
                    else
                        p.trial.state_variables.current_symbol = p.trial.state_variables.current_symbol + 1;
                    end
                elseif(p.trial.specs.timing.symbol.start_time > GetSecs - p.trial.specs.timing.symbol.display_time || p.trial.training_flags.continue_symbols)
                    %  Nothing exciting happened.  Keep showing the symbol
                    %  if we are not in the interval or if we are
                    %  continuing to show the symbols after the display
                    %  time
                    if(p.trial.state_variables.mask_trial)
                        ShowSymbolMask;
                    else
                        ShowSymbol;
                    end
                end
                
            case 'timeout'
                
                %  STATE:  timeout
                
                %  In this state we are going to give the monkey a timeout
                %  period. After that is over, end trial.
                
                if(isnan(p.trial.specs.timing.timeout.start_time))
                    fprintf('TIMEOUT state for %0.3f sec...  ',p.trial.specs.timing.timeout.duration);
                    p.trial.specs.timing.timeout.start_time = GetSecs;
                    
                elseif(p.trial.specs.timing.timeout.start_time <= GetSecs - p.trial.specs.timing.timeout.duration)
                    fprintf('Timeout elapsed.\nEND TRIAL %d.\n\n',p.trial.pldaps.iTrial);
                    p.trial.specs.timing.timeout.start_time = NaN;
                    p.trial.flagNextTrial = true;
                end
                
                
            case 'error'
                
                %  STATE:  error
                
                %  In this state we are going to give the monkey a time
                %  penalty for an error and end the trial.
                
                if(isnan(p.trial.specs.timing.error_penalty.start_time))
                    fprintf('ERROR state for %0.3f sec...  ',p.trial.specs.timing.error_penalty.duration);
                    p.trial.specs.timing.error_penalty.start_time = GetSecs;
                    pds.audio.play(p,'incorrect',1);
                    
                elseif(p.trial.specs.timing.error_penalty.start_time <= GetSecs - p.trial.specs.timing.error_penalty.duration)
                    fprintf('Error penalty elapsed.\nEND TRIAL %d.\n\n',p.trial.pldaps.iTrial);
                    p.trial.specs.timing.error_penalty.start_time = NaN;
                    p.trial.flagNextTrial = true;
                end
                
            case 'response_cue'
                
                %  STATE:  response_cue
                
                %  In this state we show a response cue.  Monkey should
                %  either press or release the joystick prior to the end of
                %  the grace period in order to convey his response.
                
                if(isnan(p.trial.specs.timing.response_cue.start_time))
                    
                    p.trial.specs.timing.response_cue.reaction_time = NaN;
                    p.trial.specs.timing.response_cue.buffer_entry_time = NaN;
                    
                    p.trial.specs.timing.response_cue.start_time = GetSecs;
                    
                    if(p.trial.training_flags.continue_symbols)
                        if(p.trial.state_variables.mask_trial)
                            ShowSymbolMask;
                        else
                            ShowSymbol;
                        end
                    end
                    ShowResponseCue;
                    ShowFixationCue;
                    
                    fprintf('RESPONSE state for trial %d.  Respond within %0.3f sec.\n',p.trial.pldaps.iTrial,p.trial.specs.timing.response_cue.grace);
                    
                elseif(p.trial.specs.timing.response_cue.start_time > GetSecs - p.trial.specs.timing.response_cue.grace)
                    
                    %  Still in grace period so check joystick as long as
                    %  he is still fixating
                    if(p.trial.state_variables.fixating)
                        
                        if(p.trial.training_flags.continue_symbols)
                            if(p.trial.state_variables.mask_trial)
                                ShowSymbolMask;
                            else
                                ShowSymbol;
                            end
                        end
                        ShowResponseCue;
                        ShowFixationCue;
                        
                        if(isnan(p.trial.specs.timing.response_cue.reaction_time))
                            if(~p.trial.state_variables.joystick_engaged)
                                p.trial.specs.timing.response_cue.reaction_time = GetSecs - p.trial.specs.timing.response_cue.start_time;
                            end
                        end
                        
                        if(p.trial.state_variables.joystick_released)
                            %  Monkey has released the joystick
                            
                            fprintf('\t%s released joystick with reaction time %0.3f sec ',p.trial.session.subject,p.trial.specs.timing.response_cue.reaction_time);
                            
                            if(~isnan(p.trial.specs.timing.response_cue.buffer_entry_time))
                                p.trial.specs.timing.response_cue.buffer_dwell_time = GetSecs - p.trial.specs.timing.response_cue.buffer_entry_time;
                                fprintf('(%0.3f sec in buffer).\n',p.trial.specs.timing.response_cue.buffer_dwell_time);
                            else
                                p.trial.specs.timing.response_cue.buffer_dwell_time = 0;
                                fprintf('(<0.0083 sec in buffer).\n');
                            end
                            
                            p.trial.specs.timing.response_cue.response_duration = GetSecs - p.trial.specs.timing.response_cue.reaction_time - p.trial.specs.timing.response_cue.start_time;
                            fprintf('\tResponse duration was %0.3f sec.\n',p.trial.specs.timing.response_cue.response_duration);
                            
                            if(p.trial.state_variables.release_trial)
                                p.trial.state_variables.trial_state = 'reward_delay';
                            else
                                p.trial.state_variables.trial_state = 'error_delay';
                            end
                            p.trial.specs.timing.response_cue.start_time = NaN;
                            p.trial.state_variables.wait_for_release = false;
                            
                        elseif(p.trial.state_variables.joystick_release_buffer)
                            
                            %  Joystick is now in the release buffer.
                            
                            if(isnan(p.trial.specs.timing.response_cue.buffer_entry_time))
                                p.trial.specs.timing.response_cue.buffer_entry_time = GetSecs;
                                
                            elseif(p.trial.specs.timing.response_cue.buffer_entry_time <= GetSecs - p.trial.specs.timing.response_cue.buffer_maximum_time)
                                %  the maximum time has elapsed and
                                %  joystick is not fully released.  Abort
                                %  the trial
                                fprintf('\t%s drifted out of engage state at %0.3f sec without fully releasing joystick.\n',p.trial.session.subject,p.trial.specs.timing.response_cue.reaction_time);
                                
                                p.trial.outcome = aborted_trial('release drift error');
                                p.trial.specs.timing.response_cue.start_time = NaN;
                                p.trial.state_variables.trial_state = 'timeout';
                            end
                            
                        elseif(p.trial.state_variables.joystick_pressed)
                            %  Monkey has pressed the joystick
                            
                            fprintf('\t%s pressed joystick with reaction time %0.3f sec ',p.trial.session.subject,p.trial.specs.timing.response_cue.reaction_time);
                            
                            if(~isnan(p.trial.specs.timing.response_cue.buffer_entry_time))
                                p.trial.specs.timing.response_cue.buffer_dwell_time = GetSecs - p.trial.specs.timing.response_cue.buffer_entry_time;
                                fprintf('(%0.3f sec in buffer).\n',p.trial.specs.timing.response_cue.buffer_dwell_time);
                            else
                                p.trial.specs.timing.response_cue.buffer_dwell_time = 0;
                                fprintf('(<0.0083 sec in buffer).\n');
                            end                            
                            p.trial.specs.timing.response_cue.response_duration = GetSecs - p.trial.specs.timing.response_cue.reaction_time - p.trial.specs.timing.response_cue.start_time;
                            
                            if(p.trial.state_variables.press_trial)
                                p.trial.state_variables.trial_state = 'reward_delay';
                            else
                                p.trial.state_variables.trial_state = 'error_delay';
                            end
                            
                            p.trial.specs.timing.response_cue.start_time = NaN;
                            p.trial.state_variables.wait_for_release = p.trial.training_flags.release_for_reward;
                        
                        elseif(p.trial.state_variables.joystick_press_buffer)
                            
                            %  Joystick is now in the press buffer.
                            
                            if(isnan(p.trial.specs.timing.response_cue.buffer_entry_time))
                                p.trial.specs.timing.response_cue.buffer_entry_time = GetSecs;
                                
                            elseif(p.trial.specs.timing.response_cue.buffer_entry_time <= GetSecs - p.trial.specs.timing.response_cue.buffer_maximum_time)
                                %  the maximum time has elapsed and
                                %  joystick is not fully pressed.  Abort
                                %  the trial
                                fprintf('\t%s drifted out of engage state at %0.3f sec without fully pressing joystick.\n',p.trial.session.subject,p.trial.specs.timing.response_cue.reaction_time);                                
                                p.trial.outcome = aborted_trial('press drift error');
                                p.trial.specs.timing.response_cue.start_time = NaN;
                                p.trial.state_variables.trial_state = 'timeout';
                            end
                        end
                    else                        
                        %  Monkey broke fixation too early.  Give him a
                        %  timeout.
                        
                        fprintf('\t%s broke fixation after %0.3f sec.\n',p.trial.session.subject,GetSecs-p.trial.specs.timing.response_cue.start_time);                        
                        p.trial.outcome = aborted_trial('fixation break');                        
                        p.trial.state_variables.trial_state = 'timeout';
                    end
                    
                else
                    %  Monkey has held joystick till end of grace period,
                    %  so give him a timeout
                    
                    fprintf('\t%s held joystick to end of response duration; this is a missed response.\n',p.trial.session.subject);
                    p.trial.specs.timing.response_cue.start_time = NaN;                    
                    p.trial.outcome = aborted_trial('miss');                    
                    p.trial.state_variables.trial_state = 'timeout';
                end
                
            case 'error_delay'
                
                %  STATE:  error_delay
                %
                %  In this state we continue to show the fixation dot while
                %  the monkey is waiting to see if he gets his reward.
                
                
                ShowFixationCue;
                
                if(isnan(p.trial.specs.timing.error_delay.start_time))
                    
                    if(p.trial.training_flags.release_for_reward && p.trial.state_variables.wait_for_release)
                        fprintf('ERROR DELAY.  %s must completely release joystick, fixate and await feedback %0.3f sec (%0.3f remain).\n',p.trial.session.subject,p.trial.specs.timing.error_delay.duration,p.trial.specs.timing.error_delay.duration -p.trial.specs.timing.response_cue.response_duration);
                    else
                        fprintf('ERROR DELAY.  %s must fixate and await feedback for %0.3f sec.\n',p.trial.session.subject,p.trial.specs.timing.error_delay.duration);
                    end
                    
                    p.trial.specs.timing.error_delay.start_time = GetSecs;
                elseif(p.trial.specs.timing.error_delay.start_time > GetSecs - p.trial.specs.timing.error_delay.duration -p.trial.specs.timing.response_cue.response_duration)
                    
                    %  Still in delay so check to make sure monkey
                    %  continues to fixate.
                    
                    if(~p.trial.state_variables.fixating)
                        fprintf('\t%s broke fixation after %0.3f sec; give him a timeout.\n',p.trial.session.subject,GetSecs - p.trial.specs.timing.error_delay.start_time);
                        
                        p.trial.outcome = aborted_trial('fixation break');
                        p.trial.state_variables.trial_state = 'timeout';
                        p.trial.specs.timing.error_delay.start_time = NaN;
                    end
                    
                    if(p.trial.training_flags.release_for_reward && p.trial.state_variables.wait_for_release && p.trial.state_variables.joystick_released)
                        p.trial.specs.timing.response_cue.response_duration =p.trial.specs.timing.response_cue.response_duration + GetSecs - p.trial.specs.timing.error_delay.start_time;
                        fprintf('\t%s released joystick at %0.3f sec; response duration was %0.3f sec.\n',p.trial.session.subject,GetSecs - p.trial.specs.timing.error_delay.start_time,p.trial.specs.timing.response_cue.response_duration);
                        p.trial.state_variables.wait_for_release = false;
                    end
                    
                elseif(p.trial.training_flags.release_for_reward && p.trial.state_variables.wait_for_release)
                    if(isnan(p.trial.specs.timing.error_delay.eligible_start_time))
                        fprintf('\t%s has exceeded the error delay and is eligible for another trial once he releases the joystick.\n',p.trial.session.subject);
                        p.trial.specs.timing.error_delay.eligible_start_time = GetSecs;
                    end
                    if(p.trial.state_variables.joystick_released)
                        p.trial.specs.timing.response_cue.response_duration =p.trial.specs.timing.response_cue.response_duration + GetSecs - p.trial.specs.timing.error_delay.start_time;
                        fprintf('\t%s released joystick at %0.3f sec; response duration was %0.3f sec.\n',p.trial.session.subject,GetSecs - p.trial.specs.timing.error_delay.start_time,p.trial.specs.timing.response_cue.response_duration);
                        p.trial.state_variables.wait_for_release = false;
                    end
                elseif(~p.trial.training_flags.release_for_reward || ~p.trial.state_variables.wait_for_release)
                    p.trial.specs.timing.error_delay.eligible_start_time = GetSecs;
                end
                
                if(~isnan(p.trial.specs.timing.error_delay.eligible_start_time) && ~p.trial.state_variables.wait_for_release)
                    
                    %  Monkey completed error delay to se can get next
                    %  trial now!
                    fprintf('\t%s completed error delay with joystick released.  He gets no reward (WOMP WOMP).\n',p.trial.session.subject);
                    p.trial.specs.timing.error_delay.start_time = NaN;
                    p.trial.specs.timing.error_delay.eligible_start_time = NaN;                    
                    p.trial.outcome = completed_trial(false);
                    p.trial.state_variables.trial_state = 'error';
                end
                
            case 'reward_delay'
                
                %  STATE:  reward_delay
                %
                %  In this state we continue to show the fixation dot.
                %  Monkey must release the joystick. Once this is done we
                %  can give him his reward!
                
                ShowFixationCue;
                
                if(isnan(p.trial.specs.timing.reward_delay.start_time))
                    
                    if(p.trial.training_flags.release_for_reward && p.trial.state_variables.wait_for_release)
                        fprintf('REWARD DELAY.  %s must release joystick, fixate and await feedback for %0.3f sec (%0.3f sec remain).\n',p.trial.session.subject,p.trial.specs.timing.reward_delay.duration,p.trial.specs.timing.reward_delay.duration -p.trial.specs.timing.response_cue.response_duration);
                    else
                        fprintf('REWARD DELAY.  %s must fixate and await feedback for %0.3f sec.\n',p.trial.session.subject,p.trial.specs.timing.reward_delay.duration);
                    end
                    
                    p.trial.specs.timing.reward_delay.start_time = GetSecs;
                elseif(p.trial.specs.timing.reward_delay.start_time > GetSecs - p.trial.specs.timing.reward_delay.duration -p.trial.specs.timing.response_cue.response_duration)
                    
                    %  Still in delay so check to make sure monkey
                    %  continues to fixate.
                    
                    if(~p.trial.state_variables.fixating)
                        fprintf('\t%s broke fixation after %0.3f sec; give him a timeout.\n',p.trial.session.subject,GetSecs - p.trial.specs.timing.reward_delay.start_time);
                        
                        p.trial.outcome = aborted_trial('fixation break');
                        p.trial.state_variables.trial_state = 'timeout';
                        p.trial.specs.timing.reward_delay.start_time = NaN;
                    end
                    
                    if(p.trial.training_flags.release_for_reward && p.trial.state_variables.wait_for_release && p.trial.state_variables.joystick_released)
                        p.trial.specs.timing.response_cue.response_duration =p.trial.specs.timing.response_cue.response_duration + GetSecs - p.trial.specs.timing.reward_delay.start_time;
                        fprintf('\t%s released joystick at %0.3f sec; response duration was %0.3f sec.\n',p.trial.session.subject,GetSecs - p.trial.specs.timing.reward_delay.start_time,p.trial.specs.timing.response_cue.response_duration);
                        p.trial.state_variables.wait_for_release = false;
                    end
                elseif(p.trial.training_flags.release_for_reward && p.trial.state_variables.wait_for_release)
                    if(isnan(p.trial.specs.timing.reward_delay.eligible_start_time))
                        fprintf('\t%s has exceeded the reward delay and is eligible for a reward once he releases the joystick.\n',p.trial.session.subject);
                        p.trial.specs.timing.reward_delay.eligible_start_time = GetSecs;
                    end
                    if(p.trial.state_variables.joystick_released)
                        p.trial.specs.timing.response_cue.response_duration =p.trial.specs.timing.response_cue.response_duration + GetSecs - p.trial.specs.timing.reward_delay.start_time;
                        fprintf('\t%s released joystick at %0.3f sec; response duration was %0.3f sec.\n',p.trial.session.subject,GetSecs - p.trial.specs.timing.reward_delay.start_time,p.trial.specs.timing.response_cue.response_duration);
                        p.trial.state_variables.wait_for_release = false;
                    end
                elseif(~p.trial.training_flags.release_for_reward || ~p.trial.state_variables.wait_for_release)
                    p.trial.specs.timing.reward_delay.eligible_start_time = GetSecs;
                end
                
                if(~isnan(p.trial.specs.timing.reward_delay.eligible_start_time) && ~p.trial.state_variables.wait_for_release)
                    
                    %  Monkey completed reward delay so he can get his
                    %  reward now!
                    fprintf('\t%s completed reward delay.  He gets a reward!\n',p.trial.session.subject);
                    p.trial.specs.timing.reward_delay.start_time = NaN;
                    p.trial.specs.timing.reward_delay.eligible_start_time = NaN;
                    
                    p.trial.outcome = completed_trial(true);
                    p.trial.state_variables.trial_state = 'reward';
                end
                
            case 'reward'
                
                %  STATE:  reward
                
                %  Provide the monkey with his just desserts.
                
                ShowFixationCue;
                
                if(isnan(p.trial.specs.timing.reward.start_time))
                    p.trial.specs.timing.reward.start_time = GetSecs;
                    pds.behavior.reward.give(p,p.trial.stimulus.reward_amount);
                    pds.audio.play(p,'reward',1);
                    
                    fprintf('REWARD:  ');
                elseif(p.trial.specs.timing.reward.start_time <= GetSecs - p.trial.stimulus.reward_amount)
                    fprintf('%s received reward for %0.3f sec.\n',p.trial.session.subject,p.trial.stimulus.reward_amount);
                    fprintf('END TRIAL %d.\n\n',p.trial.pldaps.iTrial);
                    p.trial.flagNextTrial = true;
                end
                
        end
end

%  NESTED FUNCTIONS BELOW


    function ShowFixationCue
        %  ShowFixationCue
        %
        %  This function draws a fixation sqaure
        
        win = p.trial.display.overlayptr;
        width = p.trial.specs.features.fixation.width;
        baseRect = [0 0 width width];
        centeredRect = CenterRectOnPointd(baseRect, p.trial.display.ctr(1), p.trial.display.ctr(2));
        switch p.trial.state_variables.trial_state
            case 'joystick_warning'
                color = p.trial.specs.features.joystick_warning.color;
            case 'engage'
                color = p.trial.specs.features.engage.color;
            otherwise
                color = p.trial.specs.features.fixation.color;
        end
        linewidth = p.trial.specs.features.fixation.linewidth;
        Screen('FrameRect',win,color,centeredRect,linewidth);
    end

    function ShowResponseCue
        %  ShowResponseCue
        %
        %  This function draws a cue to indicate to monkey what his
        %  repsonse should be.  It is embedded in a noise annulus.
        
        window = p.trial.display.ptr;
        cue_lum = p.trial.condition.luminance-p.trial.display.bgColor(1);
        background = p.trial.display.bgColor(1);
        sigma = p.trial.specs.features.annulus.noise_sigma;
        center = p.trial.display.ctr([1 2]);
        only_zuul.noise_ring.draw(window,cue_lum,background,sigma,center);
    end

    function ShowSymbolMask
        %  ShowSymbolMask
        %
        %  This function draws the symbol mask
        
        window = p.trial.display.overlayptr;
        centers = p.trial.specs.features.symbol.centers;
        indx = p.trial.specs.features.symbol.position_order(1:p.trial.state_variables.current_symbol);
        only_zuul.symbol_masks.draw(window,centers,indx)
    end

    function ShowSymbol
        %  ShowSymbol
        %
        %  This function draws the symbol.  For now just circles, switching
        %  based on color
        
        win = p.trial.display.overlayptr;
        order = p.trial.specs.features.symbol.position_order(1:p.trial.state_variables.current_symbol);
        color = repmat([p.trial.condition.symbol_features(order-3*(order>3)).color],3,1);
        rect = p.trial.specs.features.symbol.positions(order,:)';
        Screen('FillOval',win,color,rect);
    end

    function check_joystick_status
        %  check_joystick_status
        %
        %  This function compares the joystick against threshold and sets
        %  the flags
        
        %  If the debug flag is set then automatically set joystick status
        if(p.trial.debug_flags.joystick_zombie)
            switch p.trial.state_variables.trial_state
                case 'engage'
                    zone = 2;
                case 'response_cue'
                    if(p.trial.state_variables.release_trial)
                        zone = 1;
                    else
                        zone = 3;
                    end
                otherwise
                    zone = 1;
            end
        else
            %  Determine status of joystick against thresholds
            switch p.trial.state_variables.trial_state
                case 'joystick_warning'
                    [zone,p.trial.joystick.position] = joystick.zones(p.trial.joystick.joystick_warning);
                case 'engage'
                    [zone,p.trial.joystick.position] = joystick.zones(p.trial.joystick.engage);
                case 'response_cue'
                    if(p.trial.training_flags.relative_response_threshold)
                        if(isnan(p.trial.specs.timing.response_cue.start_time))
                            p.trial.joystick.response = p.trial.joystick.default;
                            p.trial.joystick.response_cue.threshold(1) = max(p.trial.joystick.position-3,p.trial.joystick.default.threshold(1));
                            p.trial.joystick.response_cue.threshold(2) = max(p.trial.joystick.position-2,p.trial.joystick.default.threshold(2));
                            p.trial.joystick.response_cue.threshold(3) = min(p.trial.joystick.position+2,p.trial.joystick.default.threshold(3));
                            p.trial.joystick.response_cue.threshold(4) = min(p.trial.joystick.position+3,p.trial.joystick.default.threshold(4));
                        end
                    else
                        p.trial.joystick.response = p.trial.joystick.default;
                    end
                    [zone,p.trial.joystick.position] = joystick.zones(p.trial.joystick.response);
                otherwise
                    [zone,p.trial.joystick.position] = joystick.zones(p.trial.joystick.default);
            end
        end
        %  Set joystick state variables
        p.trial.state_variables.joystick_released = zone==1;
        p.trial.state_variables.joystick_release_buffer = zone==2;
        p.trial.state_variables.joystick_engaged = zone==3;
        p.trial.state_variables.joystick_press_buffer = zone==4;
        p.trial.state_variables.joystick_pressed = zone==5;
    end

    function display_joystick_status
        %  display_joystick_status
        %
        %  This function calls the function to display the joystick status
        %  to the console screen
        
        switch p.trial.state_variables.trial_state
            case 'joystick_warning'
                joystick.display(p,p.trial.joystick.position,p.trial.joystick.joystick_warning.threshold);
            case 'engage'
                joystick.display(p,p.trial.joystick.position,p.trial.joystick.engage.threshold);
            case 'response_cue'
                if(p.trial.training_flags.relative_response_threshold)
                    joystick.display(p,p.trial.joystick.position,p.trial.joystick.response_cue.threshold);
                else
                    joystick.display(p,p.trial.joystick.position,p.trial.joystick.default.threshold);
                end
            otherwise
                joystick.display(p,p.trial.joystick.position,p.trial.joystick.default.threshold);
        end
    end

    function display_fixation_window
        %  display_fixation_window
        %
        %  This function displays the fixation window
        win = p.trial.display.overlayptr;
        width = p.trial.stimulus.fpWin;
        baseRect = [0 0 width(1) width(2)];
        centeredRect = CenterRectOnPointd(baseRect, p.trial.display.ctr(1), p.trial.display.ctr(2));
        color = p.trial.display.clut.hCyan;
        Screen('FrameRect',win,color,centeredRect);
    end

    function check_fixation_status
        %  Check fixation status
        width = p.trial.stimulus.fpWin;
        if(p.trial.eyelink.useAsEyepos)
            p.trial.state_variables.fixating = squarewindow(~p.trial.training_flags.enforce_fixation,p.trial.display.ctr(1:2)-[p.trial.eyeX p.trial.eyeY],width(1),width(2));
        else
            p.trial.state_variables.fixating = true;
        end
    end

%  Construct outcome for aborted trial
    function s = aborted_trial(mssg)
        s = struct(...
            'completed',false,...
            'abort',struct(...
            'state',p.trial.state_variables.trial_state,...
            'time',GetSecs - p.trial.trstart,...
            'message',mssg));
    end

%  Construct outcome for completed trial
    function s = completed_trial(correct)
        s = struct(...
            'completed',true,...
            'correct',correct,...
            'reaction_time',p.trial.specs.timing.response_cue.reaction_time);
    end

%  Construct outcome for interrupted trial
    function s = interrupted_trial
        if(p.trial.pldaps.quit==1)
            s = struct('interrupt','pause');
        else
            s = struct('interrupt','quit');
        end
    end
end