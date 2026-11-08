/* Host-only numerical equivalence harness; excluded from the MCU project. */
#include "dcdc_step.h"
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv)
{
    FILE *inputs, *parameters, *outputs;
    DcdcParams p;
    DcdcState s;
    float in[7], out[9], duty;
    boolean_T enabled;
    if (argc != 4) return 2;
    inputs=fopen(argv[1],"rb"); parameters=fopen(argv[2],"rb"); outputs=fopen(argv[3],"wb");
    if (!inputs || !parameters || !outputs) return 3;
    if (sizeof(DcdcParams)!=19*sizeof(float) || fread(&p,sizeof(p),1,parameters)!=1) return 4;
    memset(&s,0,sizeof(s)); dcdc_step_initialize();
    while (fread(in,sizeof(in),1,inputs)==1) {
        if (in[6]!=0) memset(&s,0,sizeof(s));
        dcdc_step((unsigned char)in[0],in[1],in[2],in[3],in[4],in[5],&s,&p,&duty,&enabled);
        out[0]=duty; out[1]=(float)enabled; out[2]=(float)s.fault; out[3]=(float)s.mode;
        out[4]=s.current_integral; out[5]=s.voltage_integral;
        out[6]=s.current_reference; out[7]=s.voltage_reference;
        out[8]=s.previous_current;
        if (fwrite(out,sizeof(out),1,outputs)!=1) return 5;
    }
    fclose(inputs); fclose(parameters); fclose(outputs);
    dcdc_step_terminate(); return 0;
}
