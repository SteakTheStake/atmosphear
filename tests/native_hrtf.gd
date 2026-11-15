extends SceneTree
## Offline native DSP measurements, independent of an output device or UI.
const RATE := 48000
var failures := 0
var report := {}
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ",message)
	if not value: failures += 1

func scene_data(headphones := true) -> Dictionary:
	return {"settings":{"ambience":1.0,"footsteps":1.0,"binaural":1.0 if headphones else 0.0},"paused":false,"position":[0,0,0],"forward":[0,0,-1],"decay":[.2,.2,.2],"wet":0}

func engine(headphones := true):
	var dsp = ClassDB.instantiate("AtmoSpatialStream")
	check(dsp.initialize(RATE),"native measured HRTF initializes")
	dsp.layout({"rooms":[],"portals":[]})
	dsp.scene(scene_data(headphones))
	dsp.render_frames(5120) # Complete output/mode envelopes at a block boundary.
	return dsp

func noise() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99173
	var samples := PackedFloat32Array()
	samples.resize(RATE)
	for i in samples.size(): samples[i]=rng.randf_range(-.15,.15)
	return samples

func params(position: Vector3, distance := -1.0) -> Dictionary:
	return {"position":position,"distance":position.length() if distance < 0 else distance,"db":0,"cutoff":20000,"pitch":1,"send_db":-120,"paths":[]}

func spatial(position: Vector3, headphones := true) -> PackedVector2Array:
	var dsp = engine(headphones)
	dsp.configure_pcm("probe",noise(),true,"Environment")
	dsp.update("probe",params(position))
	dsp.play("probe",0.0)
	return dsp.render_frames(24064)

func energy(samples: PackedVector2Array, start := 8000) -> Vector2:
	var sum := Vector2.ZERO
	for i in range(start,samples.size()): sum += samples[i]*samples[i]
	return sum

func correlation(a: PackedVector2Array,b: PackedVector2Array) -> float:
	var ab := 0.0
	var aa := 0.0
	var bb := 0.0
	for i in range(8000,mini(a.size(),b.size())):
		ab += a[i].x*b[i].x
		aa += a[i].x*a[i].x
		bb += b[i].x*b[i].x
	return ab/sqrt(maxf(aa*bb,1e-30))

func impulse_peak(samples: PackedVector2Array,at: float) -> float:
	var peak := 0.0
	for i in range(int((at-.001)*RATE),int((at+.002)*RATE)): peak=maxf(peak,absf(samples[i].x))
	return peak

func decay(rt: float) -> Dictionary:
	var dsp = engine(false)
	dsp.layout({"rooms":[{"id":"test","rect":[-100,-100,200,200],"rt":[rt,rt,rt],"wet":1.0}],"portals":[]})
	dsp.scene(scene_data(false))
	dsp.render_frames(24576)
	var samples := PackedFloat32Array()
	samples.resize(RATE)
	samples[3840] = 1.0
	dsp.configure_pcm("impulse",samples,false,"Environment")
	var data := params(Vector3(0,0,-1))
	data.db = -120
	data.send_db = 0
	dsp.update("impulse",data)
	dsp.play("impulse",0.0)
	var output: PackedVector2Array = dsp.render_frames(RATE*4)
	var edc := PackedFloat64Array()
	edc.resize(output.size())
	var total := 0.0
	for i in range(output.size()-1,-1,-1):
		total += output[i].length_squared()
		edc[i] = total
	var first := -1
	var last := -1
	for i in edc.size():
		var level := 10.0*log(maxf(edc[i]/maxf(total,1e-30),1e-30))/log(10.0)
		if first < 0 and level <= -5: first=i
		if last < 0 and level <= -35:
			last=i
			break
	var measured := float(last-first)/RATE*2.0
	check(total > .0001,"16-line room field produces a nonzero impulse tail")
	check(first >= 0 and last > first and absf(measured-rt)<rt*.15,"16-line room T30 follows RT60 target "+str(rt))
	return {"target_rt60":rt,"measured_rt60":measured,"energy":total}

func run() -> void:
	check(ClassDB.class_exists("AtmoSpatialStream"),"native audio extension is loaded")
	if not ClassDB.class_exists("AtmoSpatialStream"):
		quit(1)
		return
	var left := spatial(Vector3(-2,0,-2))
	var right := spatial(Vector3(2,0,-2))
	var front := spatial(Vector3(0,0,-2))
	var back := spatial(Vector3(0,0,2))
	var above := spatial(Vector3(0,sqrt(2),-sqrt(2)))
	var le := energy(left)
	var re := energy(right)
	var fb := correlation(front,back)
	var elevation := correlation(front,above)
	check(le.x > le.y*1.3 and re.y > re.x*1.3,"HRTF supplies the correct ipsilateral ear advantage")
	check(absf(le.x-re.y)/le.x < .15,"mirrored directions preserve mirrored ear energy")
	check(fb < .98,"front/back HRTFs differ beyond stereo pan")
	check(elevation < .98,"elevation changes the measured HRTF")
	var speaker_correlation := correlation(spatial(Vector3(0,0,-2),false),spatial(Vector3(0,0,2),false))
	check(speaker_correlation > .99999,"speaker mode uses equal-power panning without HRTF coloration")
	report.localization = {"left_energy":le,"right_energy":re,"front_back_correlation":fb,"elevation_correlation":elevation,"speaker_front_back_correlation":speaker_correlation}
	var dsp = engine(false)
	var pulse := PackedFloat32Array()
	pulse.resize(RATE)
	pulse[3840] = 1
	dsp.configure_pcm("pulse",pulse,false,"Environment")
	var data := params(Vector3(0,0,-3.43))
	data.paths=[{"id":"wall","position":[0,0,-6.86],"length":6.86,"cutoff":20000,"db":-6}]
	dsp.update("pulse",data)
	dsp.play("pulse",0.0)
	var arrivals: PackedVector2Array = dsp.render_frames(14592)
	check(impulse_peak(arrivals,.09)>.05 and impulse_peak(arrivals,.1)>.02,"shared source clock produces distance/c direct and reflected arrivals")
	check(impulse_peak(arrivals,.083)<.00001 and impulse_peak(arrivals,.109)<.001,"no arbitrary fixed diffusion copies are added")
	report.propagation = {"direct_90ms_peak":impulse_peak(arrivals,.09),"reflection_100ms_peak":impulse_peak(arrivals,.1)}
	var moving = engine(false)
	var tone := PackedFloat32Array()
	tone.resize(RATE)
	for i in tone.size(): tone[i]=sin(TAU*1000*i/RATE)*.1
	moving.configure_pcm("tone",tone,true,"Environment")
	moving.update("tone",params(Vector3(0,0,-3.43)))
	moving.play("tone",0.0)
	var motion := PackedVector2Array()
	for i in range(60):
		moving.update("tone",params(Vector3(0,0,-3.43),3.43+1.715*float(i)/60.0))
		motion.append_array(moving.render_frames(800))
	var crossings: Array[float] = []
	for i in range(24000,motion.size()-1):
		if motion[i].x <= 0 and motion[i+1].x > 0: crossings.append(i-motion[i].x/(motion[i+1].x-motion[i].x))
	var frequency := (crossings.size()-1)*RATE/(crossings[-1]-crossings[0])
	check(absf(frequency-995.0)<1.0,"fractional propagation applies one physical Doppler shift")
	report.doppler_hz=frequency
	report.ambient_pitch=[]
	for reflected in [false,true]:
		var ambient=engine(false)
		ambient.configure_pcm("wind",tone,true,"Environment")
		ambient.play("wind",0.0)
		var pcm:=PackedVector2Array()
		for i in range(60):
			var d:=params(Vector3(0,0,-3.43),3.43+1.715*float(i)/60.0)
			d.doppler=false
			if reflected:
				d.db=-120
				d.paths=[{"id":"wall","position":[0,0,-6.86],"length":6.86+3.43*float(i)/60.0,"cutoff":20000,"db":0}]
			ambient.update("wind",d)
			pcm.append_array(ambient.render_frames(800))
		var zeroes:Array[float]=[]
		for i in range(24000,pcm.size()-1):
			if pcm[i].x<=0 and pcm[i+1].x>0:zeroes.append(i-pcm[i].x/(pcm[i+1].x-pcm[i].x))
		var hz:float=(zeroes.size()-1)*RATE/(zeroes[-1]-zeroes[0])
		check(absf(hz-1000.0)<.2,"native ambient pitch stays stable while "+("reflected" if reflected else "direct")+" distance changes")
		report.ambient_pitch.append({"reflected":reflected,"frequency_hz":hz})
	var state := scene_data(false)
	state.paused=true
	moving.scene(state)
	var paused: PackedVector2Array = moving.render_frames(5120)
	check(energy(paused,3000).length_squared()<1e-15,"pause fades the entire native spatial output to silence")
	report.transitions=[]
	for action in ["stop","suspend","restart","dispose"]:
		var transition = engine(false)
		var constant := PackedFloat32Array()
		constant.resize(RATE)
		constant.fill(.1)
		transition.configure_pcm("voice",constant,true,"Environment")
		transition.update("voice",params(Vector3(0,0,-1)))
		transition.play("voice",0.0)
		var before: PackedVector2Array = transition.render_frames(8192)
		if action == "suspend": transition.suspend("voice",true)
		elif action == "restart":
			constant.fill(-.1)
			transition.configure_pcm("voice",constant,true,"Environment")
			transition.play("voice",0.0)
		else: transition.call(action,"voice")
		var after: PackedVector2Array = transition.render_frames(5120)
		var previous: Vector2 = before[-1]
		var jump := 0.0
		for sample in after:
			jump=maxf(jump,maxf(absf(sample.x-previous.x),absf(sample.y-previous.y)))
			previous=sample
		check(jump < .004,"native "+action+" fades a nonzero sample without a hard discontinuity")
		check(energy(after,4000).length_squared()<1e-15 if action != "restart" else after[-1].x < -.05,"native "+action+" completes its intended state transition")
		report.transitions.append({"action":action,"max_sample_jump":jump})
	report.decays=[]
	for rt in [.3,1.0,2.0]: report.decays.append(decay(rt))
	report.renderer=dsp.snapshot()
	print(JSON.stringify(report))
	DirAccess.make_dir_recursive_absolute("res://test-results")
	var file := FileAccess.open("res://test-results/native-hrtf.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	quit(0 if failures == 0 else 1)
