using HTTP
using JSON3

GRAPHQL_URL = "https://leetcode.com/graphql"

"""
Fetch the daily Leetcode using GraphQL.
"""
function fetch_daily_leetcode()
    graphql_query = """
    {
        activeDailyCodingChallengeQuestion {
            date
            link
            question {
                difficulty
                frontendQuestionId: questionFrontendId
                status
                title
                titleSlug
                topicTags {
                    name
                    id
                    slug
                }
            }
        }
    }
    """

    body = JSON3.write(Dict("query" => graphql_query))
    headers = [
        "Content-Type" => "application/json",
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    ]

    try
        response = HTTP.post(GRAPHQL_URL, headers, body)
        if response.status == 200
            response_data = JSON3.read(String(response.body))
            if haskey(response_data, :data) && haskey(response_data.data, :activeDailyCodingChallengeQuestion)
                question_data = response_data.data.activeDailyCodingChallengeQuestion
                question = question_data.question

                if !isempty(question.topicTags)
                    topics = join([tag.name for tag in question.topicTags], ", ")
                end
            else
                println("No daily Leetcode found")
                return nothing
            end

            return question_data
        else
            println("HTTP Error: $(response.status)")
            return nothing
        end
    catch ex
        println("Error fetching the daily leetcode: $ex")
        return nothing
    end
end

"""
Convert HTML to string
"""
function html_to_string(html_content::String)
    text = replace(html_content, r"<[^>]*>" => "")
    text = replace(text, "&nbsp;" => " ")
    text = replace(text, "&lt;" => "<")
    text = replace(text, "&gt;" => ">")
    text = replace(text, "&amp;" => "&")
    text = replace(text, "&quot;" => "\"")
    text = replace(text, "&#39;" => "'")
    text = replace(text, r"\n\s*\n" => "\n\n")  
    text = replace(text, r"^\s+" => "", count=1)  
    text = replace(text, r"\s+$" => "", count=1) 

    return text
end

"""
Fetch question details via GraphQL using its slug.
"""
function fetch_question_details(title_slug::String)
    graphql_query = """
    query questionContent(\$titleSlug: String!) {
        question(titleSlug: \$titleSlug) {
            content
            mysqlSchemas
            dataSchemas
            codeSnippets {
                lang
                langSlug
                code
            }
            exampleTestcases
        }
    }
    """
    variables = Dict("titleSlug" => title_slug)
    body = JSON3.write(Dict("query" => graphql_query, "variables" => variables))
    headers = [
        "Content-Type" => "application/json",
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    ]

    try
        response = HTTP.post(GRAPHQL_URL, headers, body)
        if response.status == 200
            response_data = JSON3.read(String(response.body))
            if haskey(response_data, :data) && haskey(response_data.data, :question)
                question = response_data.data.question
                result = Dict()

                if haskey(question, :content) && question.content !== nothing
                    result["content"] = html_to_string(question.content)
                end

                if haskey(question, :codeSnippets) && question.codeSnippets !== nothing
                    result["codeSnippets"] = question.codeSnippets
                    # Rust is the only LeetCode language with default typing similar to Julia's
                    rust_snippet = nothing
                    for snippet in question.codeSnippets
                        if snippet.langSlug == "rust"
                            rust_snippet = snippet.code
                            break
                        end
                    end

                    if rust_snippet !== nothing
                        result["rustCode"] = rust_snippet
                    end
                end

                if haskey(question, :exampleTestcases) && question.exampleTestcases !== nothing
                    result["testCases"] = question.exampleTestcases
                end

                return result
            end
        end
    catch ex
        println("Error fetching question details: $ex")
    end

    return nothing
end

"""
Convert Rust function signature to Julia equivalent
"""
function rust_to_julia_signature(rust_code::String)
    function_match = match(r"pub fn (\w+)\((.*?)\) -> (.+?) \{", rust_code)
    if function_match === nothing
        return "solve"
    end

    function_name = function_match.captures[1]
    params = function_match.captures[2]
    return_type = function_match.captures[3]

    # Rust to Julia mapping
    type_mapping = Dict(
        "i32" => "Int32",
        "i64" => "Int64", 
        "f32" => "Float32",
        "f64" => "Float64",
        "bool" => "Bool",
        "String" => "String",
        "Vec<i32>" => "Vector{Int32}",
        "Vec<i64>" => "Vector{Int64}",
        "Vec<String>" => "Vector{String}",
        "Vec<Vec<i32>>" => "Vector{Vector{Int32}}",
        "Vec<Vec<i64>>" => "Vector{Vector{Int64}}",
        "&str" => "String",
        "Option<i32>" => "Union{Int32,Nothing}",
        "Option<bool>" => "Union{Bool,Nothing}"
    )

    julia_params = []
    if !isempty(strip(params))
        param_parts = split(params, ",")
        for param in param_parts
            param = strip(param)
            if occursin(":", param)
                param_match = match(r"(\w+):\s*(.+)", param)
                if param_match !== nothing
                    param_name = param_match.captures[1]
                    rust_type = strip(param_match.captures[2])
                    julia_type = get(type_mapping, rust_type, rust_type)
                    push!(julia_params, "$(param_name)::$(julia_type)")
                end
            end
        end
    end

    julia_return_type = get(type_mapping, return_type, return_type)
    param_str = join(julia_params, ", ")
    julia_signature = "function $(function_name)($(param_str))::$(julia_return_type)"

    return function_name, julia_signature
end

"""
Extract parameter types from Julia function signature.
"""
function extract_param_types(julia_signature::String)
    param_match = match(r"function\s+\w+\((.*?)\)", julia_signature)
    if param_match === nothing
        return []
    end

    param_str = param_match.captures[1]
    if isempty(strip(param_str))
        return []
    end

    param_types = []
    param_parts = split(param_str, ",")

    for param in param_parts
        param = strip(param)
        if occursin("::", param)
            type_match = match(r".*::\s*(.+)$", param)
            if type_match !== nothing
                push!(param_types, strip(type_match.captures[1]))
            end
        end
    end

    return param_types
end

"""
Typecast arguments inside tests cases.
"""
function typecast_test_args(
    value_str::AbstractString, 
    param_types::Vector, 
    param_idx::Int = 1, 
    is_input::Bool = true
)
    value_str = strip(String(value_str))
    expected_type = length(param_types) >= param_idx ? String(param_types[param_idx]) : ""

    if startswith(value_str, "[") && endswith(value_str, "]")
        if !isempty(expected_type) && occursin("Vector", expected_type)
            return "$(expected_type)($value_str)"
        else
            # Fallback logic
            if occursin("[[", value_str) || occursin("],[", value_str)
                return "Vector{Vector{Int32}}($value_str)"
            else
                return "Vector{Int32}($value_str)"
            end
        end
    end

    # Handle booleans
    if lowercase(value_str) == "true"
        return "true"
    elseif lowercase(value_str) == "false"
        return "false"
    end

    # Handle numerics
    if occursin(r"^\d+$", value_str)
        if is_input && !isempty(expected_type) && occursin("Int", expected_type)
            return "$(expected_type)($value_str)"
        elseif is_input
            return "Int32($value_str)"
        else
            return value_str
        end
    end

    # Handle strings
    if startswith(value_str, "\"") && endswith(value_str, "\"")
        return value_str
    end

    # Fallback
    if !occursin(r"^[\d\[\]]+$", value_str) && !occursin("true", lowercase(value_str)) && !occursin("false", lowercase(value_str))
        return "\"$value_str\""
    end
end

function generate_solution_template(question_data, question_details)
    if question_data === nothing || question_details === nothing
        return nothing
    end

    question = question_data.question
    problem_id = question.frontendQuestionId
    title_slug = question.titleSlug

    filename = "../solutions/Ex$(problem_id).jl"
    if isfile(filename)
        println("Solution file already exists: $filename")
        return filename
    end

    if !isdir("../solutions")
        mkdir("../solutions")
    end

    function_name = "solve"
    julia_signature = "function solve()"

    if haskey(question_details, "rustCode")
        function_name, julia_signature = rust_to_julia_signature(question_details["rustCode"])
    end

    description = get(question_details, "content", "$(question.title)")
    test_cases = get(question_details, "testCases", "")
    param_types = extract_param_types(julia_signature)
    
    test_assertions = ""
    if !isempty(test_cases)
        example_matches = collect(eachmatch(r"Example \d+:\s*\n\s*Input:\s*([^\n]+)\s*\n\s*Output:\s*([^\n]+)", description))
        if !isempty(example_matches)
            test_cases_code = []
            for (i, match) in enumerate(example_matches)
                input_str = strip(match.captures[1])
                input_str = strip(replace(input_str, r"^[^=]*=" => ""))

                output_str = strip(match.captures[2])
                output_str = strip(replace(output_str, r"^[^=]*=" => ""))

                if length(param_types) > 1 && occursin(",", input_str)
                    input_parts = split(input_str, ",")
                    typed_inputs = []
                    for (j, part) in enumerate(input_parts)
                        part = strip(part)
                        if occursin("=", part)
                            value_part = strip(split(part, "=")[2])
                        else
                            value_part = part
                        end
                        typed_input = typecast_test_args(value_part, param_types, j, true)
                        push!(typed_inputs, typed_input)
                    end
                    typed_input = join(typed_inputs, ", ")
                else
                    typed_input = typecast_test_args(input_str, param_types, 1, true)
                end

                # Handle numeric output
                if occursin(r"^\d+(\.\d+)?$", output_str)
                    typed_output = output_str
                else
                    typed_output = typecast_test_args(output_str, [], 1, false)
                end
                test_case = "    @assert $(function_name)($(typed_input)) == $(typed_output) \"Test case $(i) failed\""
                push!(test_cases_code, test_case)
            end

            test_assertions = join(test_cases_code, "\n")
        else
            # Fallback
            test_assertions = "    # TODO: Add test cases based on the problem examples\n    # @assert $(function_name)(test_input) == expected_output \"Test failed\""

        end
    else 
        test_assertions = "    # TODO: Add test cases based on the problem examples\n    # @assert $(function_name)(test_input) == expected_output \"Test failed\""
    end
    
    template = """
    # LeetCode Problem #$(problem_id): $(question.title)
    # Difficulty: $(question.difficulty)
    # Link: https://leetcode.com$(question_data.link)
    # Date: $(question_data.date)

    \"\"\"
    $(description)
    \"\"\"

    $(julia_signature)
        # TODO: Implement solution
    end

    function test_solution()
        println("Testing solution...")
        
    $(test_assertions)
        
        println("All tests passed!")
    end

    test_solution()
    """
    
    open(filename, "w") do f
        write(f, template)
    end
    
    println("Created solution template: $filename")
    return filename

end
"""
Main
"""
function main()
    println("Fetching daily Leetcode problem...")

    question_data = fetch_daily_leetcode()
    if question_data !== nothing
        title_slug = question_data.question.titleSlug
        question_details = fetch_question_details(title_slug)

        if question_details !== nothing
            generate_solution_template(question_data, question_details)
        else
            println("Failed to fetch question details")
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
