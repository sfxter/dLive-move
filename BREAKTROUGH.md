# Breaktrough: Why The Move Engine Started Working

This project moved forward when we stopped treating dLive Director like a passive data container and started treating it like a live application with object lifecycles, async rebuilds, and UI-driven workflows.

## Core Idea

The big breaktrough was:

- low-level memory writes were often enough to change visible state
- but they were not enough to make Director rebuild all dependent runtime objects correctly
- the reliable path was to use the highest-level method we could find, ideally the same one the real UI uses

That pattern solved the hardest bugs in this project.

## What Was Going Wrong Before

We originally had the right data, but we were often applying it through paths that were too low-level:

- direct stereo config writes
- direct object writes without the app's normal notification path
- insert reassignment paths that changed routing but did not fully recreate the runtime state Director expects

This created bugs that looked random from the outside:

- a former stereo pair would become mono, but only partly
- one side of the old stereo pair would overwrite the other
- Dyn8 would attach, but show defaults
- some mixer assignments or sidechain state would disappear after the move

The important lesson was that the data itself was often not wrong. The app's internal state was incomplete.

## The Real Breaktroughs

### 1. Stereo Reconfiguration Had To Follow The UI Path

The former-stereo-pair bug on `ch3/ch4` was the clearest example.

Manual test:

- manually change `ch3+4` from stereo to mono
- then perform the move
- result: the move works

Programmatic low-level test:

- write stereo config directly
- immediately continue restoring channels
- result: `ch3/ch4` behave like they are not fully independent yet

The breaktrough was switching stereo reconfiguration to the same higher-level discovery message path Director uses, then waiting for the live stereo config to actually settle before continuing.

This changed the move from:

- "write bytes and hope the app catches up"

to:

- "ask Director to reconfigure itself the same way the UI does, then wait until it is done"

That was the reason `ch3/ch4` started behaving like real mono channels after the split.

### 2. Dyn8 Had To Be Attached Through The Real High-Level Insert Path

The Dyn8 bug was another version of the same problem.

At first, the code could:

- snapshot Dyn8 data correctly
- route inserts correctly enough to look plausible
- even write the data back

But Director still behaved as if the Dyn8 object was not fully initialized on the new destination.

The breaktrough came from matching the real `cChannel::SetInserts(...)` ABI and using it the way Director's insert form uses it.

That mattered because:

- the old call shape was wrong
- a "close enough" low-level insert change was not enough
- the real high-level attach path properly created the live Dyn8 insert state

After that, replaying Dyn8 settings started working reliably.

### 3. High-Level Attach First, Settings Replay Second

Another important lesson:

- attaching an insert and restoring its settings are not the same operation

For Dyn8 in particular, the attach step can reset the unit to defaults.

So the correct order became:

1. move channels
2. reconfigure stereo through the high-level path
3. reattach inserts through the high-level path
4. wait for Director to settle
5. replay Dyn8 settings again

That second replay was not a workaround by accident. It matched the real object lifecycle better.

### 4. "Mono After Split" Is Only True After Director Finishes Rebuilding

This became a guiding rule for the project.

Conceptually, after `ch3+4` are converted from stereo to mono, moving `ch1 -> ch3` and `ch2 -> ch4` should be no different than any mono-to-mono move.

That statement is only true after Director has fully rebuilt those channels.

So the problem was not:

- "special mono copy logic is needed"

The real problem was:

- "the destination is not a fully settled mono channel yet"

Once we respected that, many weird bugs became understandable.

## New Engineering Rule For This Project

When something breaks, first ask:

- are we using the same path the UI uses?
- are we applying data before Director has finished rebuilding objects?
- are we restoring only raw bytes, but skipping the app's own publish/refresh path?

If the answer is yes, the next move should be:

- find the higher-level entry point
- use that instead of the low-level shortcut
- add settle time only where Director is clearly rebuilding async state

## Practical Result

This rule is what unlocked:

- stable stereo-to-mono and mono-to-stereo moves
- proper `ch3/ch4` restore after splitting a stereo pair
- reliable Dyn8 movement onto new destinations
- later fixes for sidechain and insert-state refresh
- support for both Dyn8 `Insert A` and `Insert B` on moved stereo channels

## Short Version

The breaktrough was not "more retries" or "more raw copying".

The breaktrough was:

- use UI-equivalent high-level methods
- let Director finish rebuilding itself
- only then restore the saved settings

That is the main reason this project started moving forward consistently.
