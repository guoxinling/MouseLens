# MouseLens Shot System Design

## Goal

MouseLens should feel like:

- the cursor is expressive and responsive
- the camera is stable and intentional
- zoom changes belong to a shot, not to each click
- the output feels like a guided product demo, not a reactive effect stack

This document defines the next-stage `shot system` for MouseLens.

## Product Intent

MouseLens should not behave like:

- every click causes a zoom pulse
- every cursor movement drags the camera
- the camera constantly recenters and then backs out

MouseLens should behave like:

- the cursor shows immediate local feedback
- the camera only moves when attention clearly shifts
- once a shot is established, it holds
- zoom is part of the shot composition

## Core Model

The system has three independent layers:

1. `Cursor Timeline`
   Records and re-renders cursor position, click ripple, optional cursor styling.

2. `Attention Timeline`
   Interprets pointer events into candidate attention regions and shot segments.

3. `Camera Timeline`
   Produces the final camera focus and zoom path from the current shot state.

The most important principle is:

`Cursor motion`, `shot decisions`, and `camera interpolation` must remain separate.

## Shot Vocabulary

### 1. Idle Shot

The wide baseline view when there is no strong attention target.

Rules:

- zoom is near the baseline
- camera stays centered or near the last stable shot
- small cursor movement does not cause camera travel

### 2. Active Shot

A stable composed shot around a confirmed attention region.

Rules:

- has its own `anchor`
- has its own `targetZoom`
- holds for a minimum duration
- camera may gently breathe within the shot, but does not reframe aggressively

### 3. Transition Shot

The interpolation between one stable shot and another.

Rules:

- camera moves with easing, not linearly
- zoom moves toward the next shot zoom and then holds
- no immediate decay back out unless the system decides to return to idle

## Event Semantics

Pointer events should not directly drive camera actions.

Instead they only contribute attention signals:

- `move`
  weak signal
- `scroll`
  medium signal
- `click`
  strong signal

The camera never asks:

`did the user click?`

The camera asks:

`did the user establish a new area of attention strongly enough to justify a new shot?`

## Attention Region Rules

### Candidate Region

A candidate region is created when activity occurs outside the current shot's safe zone.

Each candidate tracks:

- center
- first seen time
- last seen time
- accumulated confidence
- click count

### Region Merge

Nearby events merge into one candidate region.

Purpose:

- multiple nearby clicks become one intent
- mouse motion inside the same UI cluster does not create multiple shot requests

### Region Commit

A candidate becomes a new shot only if:

- it is sufficiently far from the current shot anchor
- it survives long enough or accumulates enough confidence
- the current shot has already held for a minimum time

This prevents visual chatter.

## Shot Establishment Rules

### Rule A: Same Region

If activity stays near the current shot anchor:

- do not create a new shot
- do not retrigger zoom
- only show cursor-level feedback

### Rule B: Nearby Region

If activity moves slightly outside the center but still belongs to the same local workflow area:

- remain in the same shot
- allow very mild camera lead
- do not change shot zoom

### Rule C: New Region

If activity clearly shifts to a new region:

- create a new shot
- move camera with eased travel
- move zoom toward a new stable shot zoom
- hold after arrival

### Rule D: Return to Idle

If the user stops interacting or leaves the active area for long enough:

- optionally return to a wider shot
- return should be slow and deliberate
- never behave like automatic click-by-click recoil

## Camera Rules

### 1. Shot Anchor

Each shot owns a stable `anchor`.

The anchor is not the instantaneous cursor position.
It is the composition center for the current segment.

### 2. Shot Zoom

Each shot owns a `targetZoom`.

This zoom is determined when the shot is created based on:

- attention region size
- distance from previous shot
- output aspect ratio
- optional content density heuristics later

Important:

`targetZoom` should hold during the shot.

This replaces the current pulse-style `boost -> decay` behavior.

### 3. Within-Shot Lead

Inside a shot, the camera may drift slightly toward a slow filtered lead point.

Rules:

- use a separate `lead` point, not raw pointer coordinates
- apply low-pass smoothing to the lead point
- clamp lead displacement to a small maximum distance
- keep lead influence much smaller than shot transitions

This gives life without making the camera feel nervous.

### 4. Transition Easing

Shot transitions should use cinematic easing:

- ease out from previous shot
- settle gently into next shot
- no visible rebound

Prefer one of:

- critically damped spring
- cubic ease in/out with velocity limiting
- Bezier-like eased interpolation

Avoid:

- linear interpolation
- effect-style impulse decay as the main zoom model

## Cursor Rules

The cursor should be expressive even when the camera stays still.

Cursor layer responsibilities:

- cursor smoothing
- click ripple
- optional cursor scaling or brightness
- optional drag emphasis later

The cursor can be lively.
The camera should remain selective.

This asymmetry is desirable.

## Why Current Output Still Feels Inferior

Compared with Screen Studio-like behavior, the remaining gaps are:

### 1. Zoom is still impulse-based

Current system still applies transition boost decay.

Symptom:

- camera pushes in
- then gently backs out

Desired behavior:

- a new shot chooses a stable zoom and holds it

### 2. Camera interpolation is still too mechanical

Current keyframe playback is still mostly linear between samples.

Symptom:

- movement is smooth but not cinematic

Desired behavior:

- movement has easing and weight

### 3. Shot semantics are still geometry-first

Current system mainly uses distance and dwell to decide region changes.

Symptom:

- behavior is better, but still feels like a signal processor

Desired behavior:

- decisions should feel like editing logic

### 4. Idle return is not yet a deliberate editorial choice

Current system still risks looking like it shrinks back after activity.

Desired behavior:

- return to wide only when the moment is actually over

## Next Implementation Plan

### Phase 1: Stable Shot Zoom

Replace transient zoom boosts with persistent per-shot zoom.

Implementation:

- when a new shot commits, compute `shot.targetZoom`
- keep zoom moving toward that value until another shot replaces it
- remove click-based zoom decay as the primary mechanism

Expected result:

- solves the current "zoom backs out" feeling

### Phase 2: Explicit Shot State Machine

Introduce explicit states:

- `idle`
- `transitioning`
- `holding`

Implementation:

- camera logic should branch on shot state, not only event distance
- minimum shot hold should live at the state-machine level

Expected result:

- clearer editorial behavior

### Phase 3: Better Transition Curves

Replace simple sampled linear camera motion with eased shot interpolation.

Implementation:

- add transition progress curve
- store shot transition metadata separately from raw keyframes

Expected result:

- more premium motion feel

### Phase 4: Cursor Timeline Upgrade

Improve the reconstructed cursor independently of camera logic.

Implementation:

- smooth cursor path separately
- keep click ripple and cursor emphasis on the cursor layer only
- later add cursor variants and scaling

Expected result:

- cursor remains lively while camera remains calm

## Non-Goals for This Stage

Do not do these yet:

- content-aware UI element detection
- OCR or semantic app understanding
- full manual timeline editing
- complex NLE-style keyframe UI

The immediate goal is to make the automatic shot system feel intentional.

## Acceptance Criteria

The shot system is successful when:

- nearby rapid clicks do not create obvious zoom pumping
- small within-shot cursor movement does not visibly shake the frame
- a clearly new area causes a smooth reframing
- the camera no longer feels like it automatically recoils after every interaction
- the output feels more like a guided demo and less like a reactive effect

## Immediate Recommendation

The next code change should be:

`replace transition boost decay with persistent per-shot zoom`

This is the single highest-leverage change because it directly targets the remaining "camera backs out" problem without changing the overall architecture again.
