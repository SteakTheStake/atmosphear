"""Deterministic, original placeholder Foley. No downloads or licensed sound libraries."""
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1] / 'assets/audio'
ROOT.mkdir(parents=True, exist_ok=True)
SR = 24000
rng = np.random.default_rng(14011)

def write(name, signal):
    signal = np.asarray(signal)
    peak = np.max(np.abs(signal))
    if peak > .85:
        signal = signal * .85 / peak
    with wave.open(str(ROOT / (name + '.wav')), 'wb') as f:
        f.setnchannels(1 if signal.ndim == 1 else signal.shape[1])
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes((np.clip(signal, -1, 1) * 32767).astype('<i2').tobytes())

def time(seconds):
    return np.arange(int(SR * seconds)) / SR

def noise(n, width=1):
    x = rng.standard_normal(n)
    if width > 1:
        x = np.convolve(x, np.ones(width) / np.sqrt(width), 'same')
    return x

def bell(t, freq):
    return sum(np.sin(2*np.pi*freq*ratio*t)*np.exp(-t*decay)*amp
               for ratio, decay, amp in [(1, 2.4, .48), (2.71, 4, .18), (4.08, 7, .08)]) * np.minimum(1, t*200)

for surface in ['stone', 'wood', 'gravel']:
    for i in range(4):
        t = time(.32)
        f = rng.uniform(95, 125)
        thud = np.sin(2*np.pi*f*t) * np.exp(-t*35) * .52
        if surface == 'stone':
            x = thud + noise(len(t), 3)*np.exp(-t*65)*.3 + np.sin(2*np.pi*850*t)*np.exp(-t*55)*.12
        elif surface == 'wood':
            x = thud + np.sin(2*np.pi*180*t)*np.exp(-t*18)*.35 + noise(len(t), 5)*np.exp(-t*70)*.18
        else:
            x = thud*.45 + noise(len(t), 2)*np.exp(-t*14)*.18*(.7+.3*np.sin(2*np.pi*37*t))
        write(surface+str(i), x*np.minimum(1,t*1500))

t = time(8)
# Integer-cycle modulation and a short edge fade avoid clicks at loop boundaries.
edge = np.minimum(1, np.minimum(t, 8-t)*10)
water = noise(len(t), 8)*.12*(.8+.2*np.sin(2*np.pi*.5*t))
for start in np.arange(.1, 7.8, .23):
    u = t-start
    water += np.where(u>=0, np.sin(2*np.pi*(950*u-300*u*u))*np.exp(-np.maximum(u,0)*45)*.07, 0)
write('water', water*edge)
write('wind', noise(len(t), 100)*.14*(.65+.25*np.sin(2*np.pi*.25*t))*edge)
t = time(4)
beacon = np.zeros(len(t))
for start, freq in [(0.1, 392), (.48, 523.25)]:
    u = t-start
    beacon += np.where(u>=0, bell(np.maximum(u,0),freq), 0)
write('beacon', beacon)
t = time(.7)
write('reach', bell(t, 880)*.45)
write('empty', noise(len(t), 40)*np.exp(-t*18)*.12)
write('bump', np.sin(2*np.pi*75*t)*np.exp(-t*22)*.5)
write('probe', noise(len(t), 3)*np.exp(-t*65)*.5 + bell(t, 660)*.08)
t = time(1.2)
lever = noise(len(t), 10)*np.exp(-t*7)*.3
for start in [.05,.25,.45]:
    u=np.maximum(t-start,0)
    lever += np.where(t>=start,np.sin(2*np.pi*165*u)*np.exp(-u*40)*.45,0)
write('lever',lever)
t=time(3)
unlock=noise(len(t),25)*np.exp(-t*3)*.18
for start,f in [(.15,392),(.45,523.25),(.8,659.25),(1.1,783.99)]:
    u=np.maximum(t-start,0)
    unlock+=np.where(t>=start,bell(u,f)*.65,0)
write('unlock',unlock)
t=time(1.5)
tone=bell(t,523.25)*.6
write('left',np.column_stack([tone,np.zeros(len(t))]))
write('right',np.column_stack([np.zeros(len(t)),tone]))
print('Generated 23 original Foley and spatial landmark clips.')
