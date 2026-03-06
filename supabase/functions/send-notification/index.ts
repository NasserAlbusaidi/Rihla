import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const FCM_SERVER_KEY = Deno.env.get('FCM_SERVER_KEY')!

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

type EventPayload = {
  record: Record<string, unknown>
  type: string
  table: string
}

async function resolveActorUserId(participantId?: string) {
  if (!participantId) return null

  const { data, error } = await supabase
    .from('participants')
    .select('user_id')
    .eq('id', participantId)
    .maybeSingle()

  if (error) throw error
  return data?.user_id ?? null
}

serve(async (req) => {
  try {
    const { record, type, table } = (await req.json()) as EventPayload

    let title = ''
    let body = ''
    let tripId = ''
    let actorParticipantId = ''

    if (table === 'expenses' && type === 'INSERT') {
      title = 'New Expense Added'
      body = `${record.description ?? 'Trip expense'} - ${record.amount} ${record.currency ?? ''}`
      tripId = String(record.trip_id ?? '')
      actorParticipantId = String(record.payer_participant_id ?? '')
    } else if (table === 'settlements' && type === 'INSERT') {
      title = 'Settlement Recorded'
      body = `A payment of ${record.amount} ${record.currency ?? ''} was recorded`
      tripId = String(record.trip_id ?? '')
      actorParticipantId = String(record.payer_participant_id ?? '')
    } else {
      return new Response(JSON.stringify({ message: 'Unhandled event' }), { status: 200 })
    }

    if (!tripId) {
      return new Response(JSON.stringify({ message: 'Missing trip_id' }), { status: 400 })
    }

    const actorUserId = await resolveActorUserId(actorParticipantId)

    const { data: participants, error: participantsError } = await supabase
      .from('participants')
      .select('user_id')
      .eq('trip_id', tripId)
      .not('user_id', 'is', null)

    if (participantsError) throw participantsError

    const userIds = (participants ?? [])
      .map((participant: { user_id: string | null }) => participant.user_id)
      .filter((userId): userId is string => Boolean(userId) && userId !== actorUserId)

    if (userIds.length === 0) {
      return new Response(JSON.stringify({ message: 'No participants to notify' }), { status: 200 })
    }

    const { data: tokens, error: tokensError } = await supabase
      .from('fcm_tokens')
      .select('token')
      .in('user_id', userIds)

    if (tokensError) throw tokensError

    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ message: 'No FCM tokens found' }), { status: 200 })
    }

    const results = await Promise.allSettled(
      tokens.map((entry: { token: string }) =>
        fetch('https://fcm.googleapis.com/fcm/send', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `key=${FCM_SERVER_KEY}`,
          },
          body: JSON.stringify({
            to: entry.token,
            notification: { title, body },
            data: { tripId, table, type },
          }),
        })
      ),
    )

    const sent = results.filter((result) => result.status === 'fulfilled').length
    return new Response(
      JSON.stringify({ message: `Sent ${sent}/${tokens.length} notifications` }),
      { status: 200 },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
      { status: 500 },
    )
  }
})
