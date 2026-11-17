import {
  useAddNodes,
  useCreateSkeleton,
  useDeleteNode,
  useSetLevels,
  useUpdateNode,
  type Level,
  type LocationNode,
  type LocationSetup,
} from '../../api/locations'
import {
  levelInput,
  levelsWithKind,
  placesSkipping,
  sortLevels,
  standardKinds,
  unusedAfterDelete,
} from './locationTree'

/** The top kind of a unit that has no kinds yet: the first standard one. */
export const NEW_TOP: Level = {
  level_id: '',
  level_name: standardKinds[0],
  level_order: 1,
  requirement: 'required',
}

const byName = (levels: Level[], name: string) => levels.find((l) => l.level_name === name)

/**
 * The one-screen tree's changes, made with the existing calls only (contracts 2.2–2.6): there
 * is no kinds page, so a kind is saved the first time a place of it is added and removed when
 * its last place is deleted. Each function returns what to tell the admin.
 */
export function useTreeActions(buId: string, setup: LocationSetup) {
  const setLevels = useSetLevels(buId)
  const skeleton = useCreateSkeleton(buId)
  const update = useUpdateNode(buId)
  const add = useAddNodes(buId)
  const remove = useDeleteNode(buId)

  /**
   * The unit's first place: only the API's skeleton (2.3) can make the top one. With just the
   * top kind saved it makes that place and nothing else; renaming it to its own name clears
   * the temporary-name flag. Kinds saved earlier (a unit left half set up) are put back after.
   */
  const makeTop = async (): Promise<{ levels: Level[]; top: LocationNode }> => {
    const [first = NEW_TOP, ...rest] = sortLevels(setup.levels)
    await setLevels.mutateAsync([
      { level_id: first.level_id || null, level_name: first.level_name, requirement: 'required' },
    ])
    const tree = await skeleton.mutateAsync(undefined)
    const top = tree.nodes.find((n) => n.parent_id === null)
    const saved = sortLevels(tree.levels)[0]
    if (!top || !saved) throw new Error("We couldn't create the first place. Please try again.")
    await update.mutateAsync({ nodeId: top.node_id, name: top.name })
    if (rest.length === 0) return { levels: tree.levels, top }
    const again = await setLevels.mutateAsync([
      levelInput(saved),
      ...rest.map((l) => ({ ...levelInput(l), level_id: null })),
    ])
    return { levels: again.levels, top }
  }

  /** Adds places of one kind inside `parent` (null: the unit has no place yet). */
  const addPlaces = async (
    parent: LocationNode | null,
    kind: string,
    names: string[],
    idempotencyKey: string,
  ): Promise<string> => {
    const start = parent ? { levels: setup.levels, top: parent } : await makeTop()
    let level = byName(start.levels, kind)
    let newKind = ''
    if (!level) {
      const saved = await setLevels.mutateAsync(levelsWithKind(start.levels, kind))
      level = byName(saved.levels, kind)
      if (!level) throw new Error(`We couldn't add the kind ${kind}. Please try again.`)
      newKind =
        level.requirement === 'optional'
          ? ` ${kind} was added as "can be skipped", because places already go past it.`
          : ` Technicians will now be asked for a ${kind.toLowerCase()}. If not every place has one, click ${kind} above.`
    }
    try {
      await add.mutateAsync({
        parent_id: start.top.node_id,
        level_id: level.level_id,
        names,
        idempotencyKey,
      })
    } catch (err) {
      // No place of the new kind was made: take the kind back, so it can't block scanning.
      if (newKind) {
        await setLevels.mutateAsync(sortLevels(start.levels).map(levelInput)).catch(() => undefined)
      }
      throw err
    }
    const what = names.length === 1 ? names[0] : `${names.length} places`
    return `${what} added inside ${start.top.name}.${newKind}`
  }

  /** Deletes a place and what is inside it, then the kinds that no place uses any more. */
  const deletePlace = async (node: LocationNode): Promise<string> => {
    const unused = unusedAfterDelete(setup.levels, setup.nodes, node.node_id)
    await remove.mutateAsync(node.node_id)
    if (unused.length === 0) return `${node.name} was deleted.`
    const gone = new Set(unused.map((l) => l.level_id))
    const names = unused.map((l) => l.level_name.toLowerCase()).join(' or ')
    try {
      await setLevels.mutateAsync(
        sortLevels(setup.levels)
          .filter((l) => !gone.has(l.level_id))
          .map(levelInput),
      )
    } catch {
      return `${node.name} was deleted. No ${names} is left, but technicians would still be asked for one: mark it "can be skipped" above.`
    }
    return `${node.name} was deleted. No ${names} is left, so technicians are no longer asked for one.`
  }

  /** Why a kind can't become always asked: places already go past it. Null when it can. */
  const mustStaySkippable = (level: Level): string | null => {
    const past = placesSkipping(setup.levels, setup.nodes, level.level_id)
    return past === 0
      ? null
      : `${level.level_name} has to stay "can be skipped": ${past} ${past === 1 ? 'place has' : 'places have'} something inside that goes past it.`
  }

  /** Switches a kind between always asked and "can be skipped" (contract 2.2). */
  const setSkippable = async (level: Level, skip: boolean): Promise<string> => {
    await setLevels.mutateAsync(
      sortLevels(setup.levels).map((l) =>
        l.level_id === level.level_id
          ? { ...levelInput(l), requirement: skip ? 'optional' : 'required' }
          : levelInput(l),
      ),
    )
    return skip
      ? `${level.level_name} can now be skipped.`
      : `${level.level_name} is now always asked on the phone.`
  }

  const busy =
    setLevels.isPending ||
    skeleton.isPending ||
    update.isPending ||
    add.isPending ||
    remove.isPending
  return { addPlaces, deletePlace, mustStaySkippable, setSkippable, busy }
}
