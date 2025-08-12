## How does this work?

- Fetch daily LeetCode problem description via GraphQL
- Fetch question details via GraphQL using the problem slug
- Retrieve Rust source code from question details (Rust has the closest typing system to Julia among LeetCode-supported languages)
- Convert Rust function signature to Julia equivalent
- Generate `.jl` solution template with proper function signature and test structure
- Voilà

## How to use it?

 - Navigate to \src
 - Run `.\fetch_daily_question.jl`
 - Navigate to solution folder
 - Implement solution and run an appropriate script for testing 
