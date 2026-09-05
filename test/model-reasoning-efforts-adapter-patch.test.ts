import { readFile } from 'node:fs/promises'
import { describe, expect, it } from 'vitest'
import { patchPath } from './patch-path'

/**
 * The Models page's reasoning editor writes a display-shaped `reasoning`
 * object (`{ defaultEffort, efforts: [{ id, name }] }`) onto each model
 * entry, but the pi-ai adapter's dispatch only consumes the profile-dict
 * `reasoningEfforts` shape whose keys are the standard lowercase thinking
 * levels. Before the adapter learned to translate, the UI declaration was
 * stored but never read — custom-provider models silently lost the effort
 * picker in chat.
 */
describe('model reasoning efforts adapter patch', () => {
  it('translates the settings-UI reasoning shape into reasoningEfforts', async () => {
    const patch = await readFile(patchPath('@deepseek-ai/dsh-llm-pi-ai'), 'utf8')

    expect(patch).toContain('function resolveDeclaredEfforts(provider, entry)')
    expect(patch).toContain('function normalizeDeclaredLevel(id)')
    expect(patch).toContain('const efforts = resolveDeclaredEfforts(provider, entry) ?? entry.reasoningEfforts;')
    // Case-insensitive matching: the selector labels users copy ("Low",
    // "High", "Max") are capitalized, dispatch only knows lowercase levels.
    expect(patch).toContain('const level = id.trim().toLowerCase();')
    // The per-model default the UI writes must reach the picker metadata.
    expect(patch).toContain('defaultThinkingLevel')
    expect(patch).toContain(
      'describableReasoningLevel(resolvedModel, resolvedModel.defaultThinkingLevel ?? profile.reasoning)'
    )
  })

  it('keeps hand-declared reasoningEfforts routes authoritative', async () => {
    const patch = await readFile(patchPath('@deepseek-ai/dsh-llm-pi-ai'), 'utf8')
    // The classic dict shape must still win when both are present, and its
    // validation must be intact.
    expect(patch).toContain('?? entry.reasoningEfforts;')
    expect(patch).toContain('has an empty reasoningEfforts; declare the offered levels')
    expect(patch).toContain('reasoningEfforts offers no level beyond "off"')
  })
})
