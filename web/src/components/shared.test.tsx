import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { CheckboxList } from './CheckboxList'
import { FilePicker } from './FilePicker'
import { StatusBadge } from './StatusBadge'

describe('shared components', () => {
  it('StatusBadge shows each status the same way everywhere', () => {
    render(
      <>
        <StatusBadge status="active" />
        <StatusBadge status="retired" />
        <StatusBadge status="invited" />
      </>,
    )
    expect(screen.getByText('Active')).toBeInTheDocument()
    expect(screen.getByText('Retired')).toBeInTheDocument()
    expect(screen.getByText('Invited')).toBeInTheDocument()
  })

  it('CheckboxList adds and removes values', () => {
    const onChange = vi.fn()
    render(
      <CheckboxList
        label="Customers"
        options={[
          { value: 'c1', label: 'Nordhavn' },
          { value: 'c2', label: 'Meridian' },
        ]}
        value={['c1']}
        onChange={onChange}
      />,
    )
    fireEvent.click(screen.getByLabelText('Meridian'))
    expect(onChange).toHaveBeenLastCalledWith(['c1', 'c2'])
    fireEvent.click(screen.getByLabelText('Nordhavn'))
    expect(onChange).toHaveBeenLastCalledWith([])
  })

  it('FilePicker hands back the chosen file', () => {
    const onPick = vi.fn()
    const { container } = render(
      <FilePicker accept=".csv" hint=".csv" fileName={null} onPick={onPick} />,
    )
    const input = container.querySelector('input[type="file"]') as HTMLInputElement
    fireEvent.change(input, { target: { files: [new File(['a'], 'items.csv')] } })
    expect(onPick.mock.calls[0]?.[0]?.name).toBe('items.csv')
  })
})
