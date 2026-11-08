function c=apply_candidate(c,choice)
c.controller=@(mode,charge,target,ibat,vbat,vbus,s,p) ...
    candidate_step(mode,charge,target,ibat,vbat,vbus,s,p,choice);
c.controller_state=dcdc_initial_state();
c.controller_state.fixed_working_point=single(0);
c.controller_state.hysteresis_mode=uint8(0);
end
