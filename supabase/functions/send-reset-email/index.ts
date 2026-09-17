// Supabase Edge Function for Sending Password Reset Emails
// Using Resend API for email delivery

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  try {
    const { to, name, code } = await req.json()

    // Validate inputs
    if (!to || !code) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: to, code' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Get Resend API key from environment
    const resendApiKey = Deno.env.get('RESEND_API_KEY')
    
    if (!resendApiKey) {
      console.error('RESEND_API_KEY not configured')
      // Don't fail completely - just log and return success
      // This allows the reset flow to continue during development
      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'Email service not configured - check logs for code',
          dev_code: code // REMOVE THIS IN PRODUCTION
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Send email via Resend
    const emailResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'InfinityWash <noreply@infinitywash.com>', // Change to your domain
        to: [to],
        subject: 'Password Reset Code - InfinityWash',
        html: `
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
              .container { max-width: 600px; margin: 0 auto; padding: 20px; }
              .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
              .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
              .code-box { background: white; border: 2px solid #667eea; border-radius: 10px; padding: 20px; margin: 20px 0; text-align: center; }
              .code { font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #667eea; font-family: 'Courier New', monospace; }
              .footer { text-align: center; margin-top: 20px; color: #666; font-size: 12px; }
              .warning { background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <h1>🔐 Password Reset Request</h1>
              </div>
              <div class="content">
                <p>Hello ${name || 'there'},</p>
                <p>You requested to reset your password for your InfinityWash account.</p>
                <p><strong>Your verification code is:</strong></p>
                
                <div class="code-box">
                  <div class="code">${code}</div>
                </div>

                <div class="warning">
                  ⏰ <strong>This code expires in 15 minutes</strong>
                </div>

                <p>Enter this code in the app to continue with your password reset.</p>
                
                <p><strong>Security Tips:</strong></p>
                <ul>
                  <li>This code can only be used once</li>
                  <li>Don't share this code with anyone</li>
                  <li>If you didn't request this, you can safely ignore this email</li>
                </ul>

                <hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;">

                <p style="color: #666; font-size: 14px;">
                  If you didn't request a password reset, please ignore this email or contact support if you're concerned about your account security.
                </p>
              </div>
              <div class="footer">
                <p>© ${new Date().getFullYear()} InfinityWash. All rights reserved.</p>
                <p>This is an automated message, please do not reply to this email.</p>
              </div>
            </div>
          </body>
          </html>
        `,
      }),
    })

    if (!emailResponse.ok) {
      const errorText = await emailResponse.text()
      console.error('Resend API error:', errorText)
      throw new Error(`Failed to send email: ${errorText}`)
    }

    const result = await emailResponse.json()
    console.log('Email sent successfully:', result)

    return new Response(
      JSON.stringify({ 
        success: true,
        message: 'Password reset email sent successfully',
        email_id: result.id
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Password reset email error:', error)
    
    // Return success anyway to not block the reset flow
    // Log the error but don't fail the user's request
    return new Response(
      JSON.stringify({ 
        success: true,
        message: 'Reset request processed',
        warning: 'Email delivery may have failed - check logs',
        error: error.message
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
