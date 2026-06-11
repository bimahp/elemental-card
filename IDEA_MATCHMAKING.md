Roblox TCG Matchmaking Architecture Summary
Core Idea

There is no central matchmaking server.

Every Shop server runs the same systems:

Shop Server
├─ Matchmaker
├─ Table Manager
├─ Server Heartbeat
└─ Duel System

Any server can participate in matchmaking.

1. Global Matchmaking Queue

When a player presses Matchmaking:

Queue:AddAsync({
    UserId = player.UserId,
    ServerId = game.JobId
})

stored in MemoryStore.

Example:

Queue

Alice (Server A)
Bob   (Server B)
2. Match Found

Every Shop server periodically tries:

TryCreateMatch()

One server successfully pops:

Alice
Bob

from the queue.

MemoryStore operations are atomic, so only one server can obtain them.

3. Server Availability Registry

Each Shop server publishes:

{
    JobId = game.JobId,
    FreeTables = 3,
    Players = 15
}

every few seconds to MemoryStore.

Example:

Server Registry

Server A -> 3 free tables
Server B -> 1 free table
Server C -> 0 free tables

This registry is only a hint, not guaranteed truth.

4. Select Destination Server

The server that found the match chooses a candidate server:

Prefer:
- More free tables
- Lower population
- Existing duel activity

Example:

Server A selected
5. Teleport Players

If Alice is already in Server A:

Alice stays
Bob teleports to Server A

Otherwise:

Alice teleports
Bob teleports
6. Destination Server Is Authority

When players arrive:

FindFreeTable()

The destination server performs the final validation.

Never trust the registry.

Example:

Registry says:
  FreeTables = 1

Reality:
  FreeTables = 0

Destination server decides what happens next.

7. Recovery Logic
Case A: Table Available
Assign Table 7
Seat Players
Start Duel
Case B: Reserved Table Lost
Table 7 occupied unexpectedly

Server:

FindAnotherTable()

Players never notice.

Case C: No Tables Available
ReserveServer(shopPlaceId)
Teleport both players

Create a new Shop instance.

8. Table Ownership

Tables are server-owned resources.

Players never directly sit.

Instead:

[E] Sit

actually means:

RemoteEvent:FireServer("RequestSit")

Server validates:

Table free?
Player eligible?
Not reserved?

Only then:

AssignPlayerToTable()
9. Recommended Table States
FREE
RESERVED
OCCUPIED
FREE
[ E ] Sit
RESERVED
Match Starting...

Nobody can interact.

OCCUPIED
Alice vs Bob

Spectators can watch.

10. Physical Sitting

Prefer not to use Roblox Seat objects.

Instead:

Character:PivotTo()
PlaySitAnimation()

The server controls positioning.

This avoids:

Seat ownership issues
Physics glitches
Teleport bugs
Race conditions
Final Architecture
MemoryStore
│
├─ Match Queue
├─ Server Registry
└─ Temporary Reservations
Shop Server
│
├─ Matchmaker
├─ Table Manager
├─ Duel System
└─ Spectators

Flow:

Player queues
      ↓
MemoryStore Queue
      ↓
Any server finds match
      ↓
Choose destination server
      ↓
Teleport players
      ↓
Destination server validates table
      ↓
Seat players
      ↓
Duel starts above table
Most Important Rule
Queue = Truth
Destination Server = Truth
Server Registry = Hint

Never trust availability data published by another server. Use it only to choose a likely destination, then let the destination server make the final decision when the players arrive. This keeps the system robust even when servers are slightly out of sync.