defmodule ShaderApiWeb.ShaderController do
  use ShaderApiWeb, :controller

  defp request_shader_from_llm(description) do
    # Updated prompt for WebGL compatibility
    prompt2d = """
Generate GLSL shaders for WebGL that render a fullscreen 2D visual effect using a quad drawn with `gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)`.

The effect should match the following description:
"#{description}"

Requirements:
- Vertex shader must use attribute `a_position` and output to `gl_Position`.
- Fragment shader should use `precision mediump float`.
- Use `uniform vec2 iResolution` and `uniform float iTime` if needed.
- Do not use any 3D transforms or normals — keep everything 2D and procedural.

Ensure the code works with `gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)` on a fullscreen quad.

Your response MUST be a valid JSON object with the following structure and no other text:
{
  \"vertex_shader\": \"<Your GLSL vertex shader code here>\",
  \"fragment_shader\": \"<Your GLSL fragment shader code here>\"
}

"""
    prompt = """ 
Generate GLSL shaders for a ShaderMaterial in Three.js.

The effect should match the following description:
"#{description}"

Requirements:
- Output valid vertex and fragment shaders
- Do NOT redeclare built-in attributes/uniforms:
  * position (attribute)
  * modelViewMatrix, projectionMatrix (uniforms)
- You may define `varying` variables
- Use uniforms: `uniform float iTime;`, `uniform vec2 iResolution;`

Your response MUST be a valid JSON object with the following structure and no other text:
{
  \"vertex_shader\": \"<Your GLSL vertex shader code here>\",
  \"fragment_shader\": \"<Your GLSL fragment shader code here>\"
}

"""
    gemini_key = Application.fetch_env!(:shader_api, :gemini_api_key)
    
    try do
      resp = Req.post!(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=#{gemini_key}",
        json: %{
          contents: [
            %{parts: [%{text: prompt}]}
          ]
        }
      )

      raw_response = 
        resp.body
        |> get_in(["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])

      # Clean and parse the JSON response
      cleaned_response = sanitize_shader_code(raw_response)
      
      case Jason.decode(cleaned_response) do
        {:ok, %{"vertex_shader" => vertex_shader, "fragment_shader" => fragment_shader}} ->
          # Validate both shaders contain void main
          if String.contains?(vertex_shader, "void main") and String.contains?(fragment_shader, "void main") do
            {:ok, %{
              vertex_shader: vertex_shader,
              fragment_shader: fragment_shader,
              raw_code: format_raw_code(vertex_shader, fragment_shader)
            }}
          else
            {:error, %{
              error: "Generated shaders missing void main function",
              raw_code: cleaned_response
            }}
          end
        
        {:ok, _} ->
          {:error, %{
            error: "Invalid JSON format - missing required shader fields",
            raw_code: cleaned_response
          }}
        
        {:error, _json_error} ->
          # Fallback: try to extract shaders from non-JSON response
          case extract_shaders_from_text(cleaned_response) do
            {:ok, result} -> {:ok, result}
            {:error, _} ->
              {:error, %{
                error: "Failed to parse LLM response as JSON",
                raw_code: cleaned_response
              }}
          end
      end

    rescue
      e -> 
        {:error, %{
          error: "Network or API error: #{Exception.message(e)}",
          raw_code: ""
        }}
    end
  end

  # Helper function to clean shader code response
  defp sanitize_shader_code(code) when is_binary(code) do
    code
    |> String.trim()
    # Remove markdown code blocks if present
    |> String.replace(~r/```json\s*/, "")
    |> String.replace(~r/```\s*$/, "")
    |> String.replace(~r/^```\s*/, "")
    |> String.trim()
  end

  defp sanitize_shader_code(_), do: ""

  # Helper function to format raw code for display
  defp format_raw_code(vertex_shader, fragment_shader) do
    """
    // VERTEX SHADER
    #{vertex_shader}

    // FRAGMENT SHADER
    #{fragment_shader}
    """
  end

  # Fallback parser for when LLM doesn't return proper JSON
  defp extract_shaders_from_text(text) do
    # Try to extract vertex and fragment shaders from text
    vertex_pattern = ~r/(?:vertex.*?shader|VERTEX.*?SHADER)(.*?)(?=fragment.*?shader|FRAGMENT.*?SHADER|$)/ims
    fragment_pattern = ~r/(?:fragment.*?shader|FRAGMENT.*?SHADER)(.*?)(?=vertex.*?shader|VERTEX.*?SHADER|$)/ims
    
    vertex_match = Regex.run(vertex_pattern, text)
    fragment_match = Regex.run(fragment_pattern, text)
    
    case {vertex_match, fragment_match} do
      {[_, vertex_code], [_, fragment_code]} ->
        vertex_shader = String.trim(vertex_code)
        fragment_shader = String.trim(fragment_code)
        
        if String.contains?(vertex_shader, "void main") and String.contains?(fragment_shader, "void main") do
          {:ok, %{
            vertex_shader: vertex_shader,
            fragment_shader: fragment_shader,
            raw_code: format_raw_code(vertex_shader, fragment_shader)
          }}
        else
          {:error, "Could not extract valid shaders"}
        end
      
      _ ->
        {:error, "Could not parse shader format"}
    end
  end

  # Update your API endpoint handler to use the new format
  def generate(conn, %{"description" => description}) do
    case request_shader_from_llm(description) do
      {:ok, result} ->
        conn
        |> put_status(200)
        |> json(result)
      
      {:error, error_result} ->
        conn
        |> put_status(400)
        |> json(error_result)
    end
  end

end
