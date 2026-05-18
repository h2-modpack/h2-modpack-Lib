# Game Object State

Game-object state is a Lib-owned namespace on live game tables such as `CurrentRun`, room data, loot data, or other object-like game structures.

Use it when state should follow the lifetime of a specific game object. It is not persisted, staged, hashed, profiled, or reset by Lib.

## Normal Shape

```lua
local runState = lib.gameObject.get(CurrentRun, PACK_ID, MODULE_ID, "run", function()
    return {
        ForcedNPCPending = {},
        NPCEncounterSeen = {},
    }
end)
```

The namespace has four parts:

- `object`: the live game table
- `packId`: pack namespace
- `moduleId`: module namespace inside the pack
- `key`: state bucket inside the module namespace

Lib stores the bucket under one private root on the object so modules do not attach ad hoc top-level keys.

## Public Surface

Use:

- `lib.gameObject.get(object, packId, moduleId, key, factory?)`
- `lib.gameObject.peek(object, packId, moduleId, key)`
- `lib.gameObject.clear(object, packId, moduleId, key)`

`get(...)` creates the bucket when missing. The optional factory runs only on first creation and must return a table.

`peek(...)` returns an existing bucket without creating it.

`clear(...)` removes one bucket and prunes empty namespace tables.

## When To Use It

Use game-object state for:

- per-run transient state attached to `CurrentRun`
- per-room state attached to room tables
- per-loot or per-encounter state attached to game object tables
- data that should disappear when the game object disappears

Use managed storage instead when the value is module configuration or should persist through config.

## Common Mistakes

- Do not store config settings in game-object state.
- Do not attach module keys directly to game tables.
- Do not use object state for values that must participate in hashes or profiles.
- Do not let the factory return non-table values.

See also:
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [../../../API.md](../../../API.md)
