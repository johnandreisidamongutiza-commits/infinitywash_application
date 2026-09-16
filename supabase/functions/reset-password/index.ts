// Supabase Edge Function for Password Reset
// This function is required because updating user passwords requires admin privileges

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    // Get the authorization header to verify the request
    const authHeader = req.headers.get('Authorization')!
    
    // Parse request body
    const { token_id, new_password } = await req.json()

    // Create Supabase client with service role key (has admin privileges)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    // 1. Verify the token exists and is valid
    const { data: token, error: tokenError } = await supabaseAdmin
      .from('password_reset_tokens')
      .select('id, email, expires_at, used')
      .eq('id', token_id)
      .single()

    if (tokenError || !token) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired reset token' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // 2. Check if token is already used
    if (token.used) {
      return new Response(
        JSON.stringify({ error: 'This reset link has already been used' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // 3. Check if token has expired
    const expiresAt = new Date(token.expires_at)
    if (new Date() > expiresAt) {
      return new Response(
        JSON.stringify({ error: 'Reset link has expired' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // 4. Get the user by email
    const { data: { users }, error: userError } = await supabaseAdmin.auth.admin.listUsers()
    
    const user = users?.find(u => u.email === token.email)
    
    if (!user) {
      return new Response(
        JSON.stringify({ error: 'User not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // 5. Update the user's password using admin API
    const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
      user.id,
      { password: new_password }
    )

    if (updateError) {
      throw updateError
    }

    // 6. Mark the token as used
    await supabaseAdmin
      .from('password_reset_tokens')
      .update({
        used: true,
        verified_token: token_id
      })
      .eq('id', token_id)

    // 7. Return success
    return new Response(
      JSON.stringify({ 
        success: true, 
        message: 'Password reset successfully' 
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Password reset error:', error)
    return new Response(
      JSON.stringify({ 
        error: error.message || 'Internal server error' 
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
