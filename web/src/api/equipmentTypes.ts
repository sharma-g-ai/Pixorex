import { useMutation, useQuery } from '@tanstack/react-query'
import { api, unwrap } from './client'
import type { components } from './generated/s3'
import { useRefreshingMutation } from './useRefreshingMutation'

export type EquipmentType = components['schemas']['EquipmentType']
export type Field = components['schemas']['Field']
export type FieldInput = components['schemas']['FieldInput']
export type DataType = components['schemas']['DataType']
export type SuggestedField = components['schemas']['SuggestedField']

const typesKey = (buId: string) => ['equipment-types', buId] as const
const typeKey = (typeId: string) => ['equipment-type', typeId] as const

/** Contract 2.10: the unit's register of types. */
export function useEquipmentTypes(buId: string) {
  return useQuery({
    queryKey: typesKey(buId),
    queryFn: async () =>
      unwrap(
        await api.GET('/business-units/{buId}/equipment-types', { params: { path: { buId } } }),
      ).items,
  })
}

/** Contract 2.12: one type with its fields in order. */
export function useEquipmentType(typeId: string) {
  return useQuery({
    queryKey: typeKey(typeId),
    queryFn: async () =>
      unwrap(await api.GET('/equipment-types/{typeId}', { params: { path: { typeId } } })),
  })
}

/** Any type change re-reads the register and, when given, the open type. */
function useTypeChange<Vars, Result>(
  buId: string,
  typeId: string | null,
  call: (v: Vars) => Promise<Result>,
) {
  return useRefreshingMutation(call, typeId ? [typesKey(buId), typeKey(typeId)] : [typesKey(buId)])
}

export interface CreateType {
  name: string
  created_via: 'blank' | 'copy' | 'ai_assist'
  copied_from_type_id?: string
  fields?: FieldInput[]
}

/** Contract 2.11: a new not-published type (blank, copy or AI-assist). */
export function useCreateType(buId: string) {
  return useTypeChange(
    buId,
    null,
    async ({ body, idempotencyKey }: { body: CreateType; idempotencyKey: string }) =>
      unwrap(
        await api.POST('/business-units/{buId}/equipment-types', {
          params: { path: { buId }, header: { 'Idempotency-Key': idempotencyKey } },
          body,
        }),
      ),
  )
}

/** Contract 2.13: rename (not published only). */
export function useRenameType(buId: string, typeId: string) {
  return useTypeChange(buId, typeId, async (name: string) =>
    unwrap(
      await api.PATCH('/equipment-types/{typeId}', {
        params: { path: { typeId } },
        body: { name },
      }),
    ),
  )
}

/** Contract 2.14: delete (not published only). */
export function useDeleteType(buId: string, typeId: string) {
  return useTypeChange(buId, null, async () =>
    unwrap(await api.DELETE('/equipment-types/{typeId}', { params: { path: { typeId } } })),
  )
}

/** Contract 2.19: publish and lock; creates the extraction contract. */
export function usePublishType(buId: string, typeId: string) {
  return useTypeChange(buId, typeId, async () =>
    unwrap(await api.POST('/equipment-types/{typeId}/publish', { params: { path: { typeId } } })),
  )
}

/** Contract 2.15: adds a field at the end. */
export function useAddField(buId: string, typeId: string) {
  return useTypeChange(
    buId,
    typeId,
    async ({ body, idempotencyKey }: { body: FieldInput; idempotencyKey: string }) =>
      unwrap(
        await api.POST('/equipment-types/{typeId}/fields', {
          params: { path: { typeId }, header: { 'Idempotency-Key': idempotencyKey } },
          body,
        }),
      ),
  )
}

/** Contract 2.16: changes a field (also the Required / Critical toggles). */
export function useUpdateField(buId: string, typeId: string) {
  return useTypeChange(
    buId,
    typeId,
    async ({ fieldId, ...body }: Partial<FieldInput> & { fieldId: string }) =>
      unwrap(
        await api.PATCH('/equipment-types/{typeId}/fields/{fieldId}', {
          params: { path: { typeId, fieldId } },
          body,
        }),
      ),
  )
}

/** Contract 2.17: deletes a field. */
export function useDeleteField(buId: string, typeId: string) {
  return useTypeChange(buId, typeId, async (fieldId: string) =>
    unwrap(
      await api.DELETE('/equipment-types/{typeId}/fields/{fieldId}', {
        params: { path: { typeId, fieldId } },
      }),
    ),
  )
}

/** Contract 2.18: the full field order. */
export function useReorderFields(buId: string, typeId: string) {
  return useTypeChange(buId, typeId, async (fieldIds: string[]) =>
    unwrap(
      await api.PUT('/equipment-types/{typeId}/field-order', {
        params: { path: { typeId } },
        body: { field_ids: fieldIds },
      }),
    ),
  )
}

/** Contract 2.20: AI reads a label photo and suggests fields; nothing is saved. */
export function useSuggestFields(buId: string) {
  return useMutation({
    mutationFn: async ({ name, image }: { name: string; image: File }) =>
      unwrap(
        await api.POST('/business-units/{buId}/equipment-types/ai-suggest', {
          params: { path: { buId } },
          // The generated type says string; the request is a real multipart upload.
          body: { name, image: image as unknown as string },
          bodySerializer: (body) => {
            const form = new FormData()
            form.append('name', body.name)
            form.append('image', body.image as unknown as Blob)
            return form
          },
        }),
      ).suggested_fields,
  })
}
