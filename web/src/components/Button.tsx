import type { ButtonHTMLAttributes } from 'react'
import { buttonClasses, type ButtonVariant } from './buttonClasses'

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & { variant?: ButtonVariant }

export function Button({
  variant = 'primary',
  className = '',
  type = 'button',
  ...rest
}: ButtonProps) {
  return <button type={type} className={`${buttonClasses(variant)} ${className}`} {...rest} />
}
