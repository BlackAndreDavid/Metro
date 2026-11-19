#!/usr/bin/env python3
"""Deterministic, original noise-based footsteps. Only the selected pair is retained.
Optional --reference measures a local walking WAV; no reference samples are copied.
Uses Python standard library only.
"""
import argparse, json, math, random, struct, wave
from pathlib import Path
RATE=22050
ROOT=Path(__file__).resolve().parents[1]
def synth(mode, candidate):
    rng=random.Random(410+candidate)
    period=.40 if mode=='walk' else .24
    count=round(RATE*period)*4
    result=[0.0]*count
    for step in range(4):
        low=prev=0.0
        duration=(.20+.015*candidate) if mode=='walk' else .105
        for i in range(int(RATE*duration)):
            t=i/RATE;n=rng.uniform(-1,1);low+=.12*(n-low)
            if mode=='walk':
                env=math.sin(math.pi*t/duration)**2
                # Broad soft fabric/gravel friction, without a tonal pulse.
                sample=(n*.18+low*.65)*env*(.34+.025*candidate)
            else:
                attack=min(t/.003,1);env=attack*math.exp(-t*(48+candidate*6))
                body=math.sin(2*math.pi*(155+candidate*12)*t)*math.exp(-t*35)
                sample=(.50*body+.40*(n-prev)+low*.25)*env*.5
            prev=n
            result[step*round(RATE*period)+i]+=sample*(1 if step%2 else .93)
    return result

def metrics(values, rate=RATE):
    rms=math.sqrt(sum(x*x for x in values)/len(values))
    return dict(duration=round(len(values)/rate,4),rms=round(rms,6),peak=round(max(map(abs,values)),6),seam=round(abs(values[0]-values[-1]),6),roughness=round(math.sqrt(sum((a-b)**2 for a,b in zip(values,values[1:]))/len(values))/max(rms,1e-9),5))
def write(path,values):
    with wave.open(str(path),'wb') as f:
        f.setparams((1,2,RATE,0,'NONE','not compressed'));f.writeframes(struct.pack('<'+'h'*len(values),*(round(x*32767) for x in values)))
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--reference',type=Path);args=parser.parse_args()
    target=ROOT/'Game/assets/audio/footsteps';target.mkdir(parents=True,exist_ok=True)
    candidates=[{mode:metrics(synth(mode,c)) for mode in ('walk','run')} for c in range(3)]
    assert all(m['peak'] < 1 and m['seam'] == 0 for c in candidates for m in c.values())
    # Prefer moderate friction and a shorter, drier running transient, subject to no clipping/seam.
    scores=[abs(c['walk']['rms']-.047)+abs(c['run']['rms']-.044) for c in candidates]
    selected=min(range(3),key=lambda c:scores[c])
    for mode in ('walk','run'):write(target/(mode+'_loop.wav'),synth(mode,selected))
    report={'seed':410,'sample_rate':RATE,'candidates':candidates,'selected':selected+1,'selection':'Objective RMS targets: walk 0.047, run 0.044; all candidates checked for clipping and zero loop seam. Subjective listening remains available in game.','reference':{'url':'https://github.com/KenneyNL/Starter-Kit-3D-Platformer','commit':'3fa8a04b1c01ab23db43123d4ce814a34c3fc7f0','asset':'sounds/walking.ogg','license':'CC0 (README assets license)','use':'Temporal/tail reference only; generated output contains no source samples.'}}
    if args.reference:
        with wave.open(str(args.reference),'rb') as f:
            raw=f.readframes(f.getnframes()); vals=struct.unpack('<'+'h'*(len(raw)//2),raw)
            report['reference']['analysis']=metrics([x/32768 for x in vals],f.getframerate()*f.getnchannels())
    (target/'evaluation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Selected candidate',selected+1, json.dumps(candidates[selected]))
if __name__=='__main__':main()
