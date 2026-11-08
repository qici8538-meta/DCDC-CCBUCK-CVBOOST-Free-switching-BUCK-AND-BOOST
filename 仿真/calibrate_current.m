function [offset_raw,ampere_per_pin_volt]=calibrate_current(i_zero,ref_zero,i_known,ref_known,known_ampere,adc_reference)
% Averaged RAW ADC counts at true 0 A and a meter's known current.
% I is adc_feedback.raw[0], REF is raw[3]. Never writes firmware files.
if nargin<6,adc_reference=3.3;end
values=[i_zero,ref_zero,i_known,ref_known];
validateattributes(values,{'numeric'},{'vector','numel',4,'finite','>=',0,'<=',4095});
validateattributes(known_ampere,{'numeric'},{'scalar','finite','nonzero'});
validateattributes(adc_reference,{'numeric'},{'scalar','finite','positive'});
offset_raw=double(i_zero-ref_zero);
span=double(i_known-ref_known)-offset_raw;
assert(abs(span)>100,'Calibration points too close.');
ampere_per_pin_volt=known_ampere/(span*adc_reference/4095);
assert(ampere_per_pin_volt>0 && ampere_per_pin_volt<10,'Check polarity and calibration data.');
if nargout==0
    fprintf('#define ADC_CURRENT_OFFSET_RAW  %.9ff\n',offset_raw);
    fprintf('#define ADC_CURRENT_A_PER_PIN_V %.9ff\n',ampere_per_pin_volt);
end
end
