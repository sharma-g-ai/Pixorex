import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { ActionMenu } from './ActionMenu'

const setup = () => {
  const rename = vi.fn()
  const remove = vi.fn()
  render(
    <ActionMenu
      label="More for Bin 01"
      actions={[
        { label: 'Rename', onSelect: rename },
        { label: 'Delete', onSelect: remove, danger: true },
      ]}
    />,
  )
  return { rename, remove, button: screen.getByRole('button', { name: 'More for Bin 01' }) }
}

describe('ActionMenu', () => {
  it('GIVEN the button THEN the actions are hidden until it is pressed', () => {
    const { button } = setup()
    expect(button).toHaveAttribute('aria-expanded', 'false')
    expect(screen.queryByRole('menu')).not.toBeInTheDocument()
    fireEvent.click(button)
    expect(button).toHaveAttribute('aria-expanded', 'true')
    expect(screen.getAllByRole('menuitem').map((i) => i.textContent)).toEqual(['Rename', 'Delete'])
    expect(screen.getByRole('menuitem', { name: 'Rename' })).toHaveFocus()
  })

  it('GIVEN an action WHEN picked THEN it runs once and the menu closes', () => {
    const { rename, remove, button } = setup()
    fireEvent.click(button)
    fireEvent.click(screen.getByRole('menuitem', { name: 'Delete' }))
    expect(remove).toHaveBeenCalledTimes(1)
    expect(rename).not.toHaveBeenCalled()
    expect(screen.queryByRole('menu')).not.toBeInTheDocument()
  })

  it('GIVEN the open menu WHEN Esc or a click outside THEN it closes and nothing runs', () => {
    const { rename, remove, button } = setup()
    fireEvent.click(button)
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(screen.queryByRole('menu')).not.toBeInTheDocument()
    expect(button).toHaveFocus()
    fireEvent.click(button)
    fireEvent.click(screen.getByRole('button', { name: 'Close menu' }))
    expect(screen.queryByRole('menu')).not.toBeInTheDocument()
    expect(rename).not.toHaveBeenCalled()
    expect(remove).not.toHaveBeenCalled()
  })

  it('GIVEN the open menu WHEN arrow keys THEN focus moves between the actions and wraps', () => {
    const { button } = setup()
    fireEvent.click(button)
    const menu = screen.getByRole('menu')
    fireEvent.keyDown(menu, { key: 'ArrowDown' })
    expect(screen.getByRole('menuitem', { name: 'Delete' })).toHaveFocus()
    fireEvent.keyDown(menu, { key: 'ArrowDown' })
    expect(screen.getByRole('menuitem', { name: 'Rename' })).toHaveFocus()
    fireEvent.keyDown(menu, { key: 'End' })
    expect(screen.getByRole('menuitem', { name: 'Delete' })).toHaveFocus()
  })
})
