#= Run this script interactively: `julia --project -i runtests.jl`
... or with arguments `julia --project runtests.jl [testfiles...]` =#

cd(dirname(@__FILE__))
# using Pkg; Pkg.activate(".") # TODO: Multivectors can't be in Project.toml for Pkg.test to work

using Random, Test, Coverage
using Revise, Multivectors

const project_root = pathof(Multivectors) |> dirname |> dirname

alltests() = setdiff(filter(endswith(".jl"), readdir()), [basename(@__FILE__)])

test(files::String...) = test(files)
function test(files=alltests())
	@testset "$file" for file in files
		include(file)
	end
	nothing
end

function coverage()
	clear_coverage_files()
	run(`julia --code-coverage --project runtests.jl`)
	score()
end

function score()
	coverage = process_folder(joinpath(project_root, "src"))
	covered, total = get_summary(coverage)
	percentage = round(100covered/total, digits=2)
	@info "Overall coverage: $percentage%"
end

clear_coverage_files() = run(`bash -c "rm $project_root/**/*.cov"`)


if isempty(ARGS)
	@info """Run this script in interactive mode, and call:
		 - `test("testfile1", "testfile2", ...)`
		   (without `.jl` extensions) to run tests
		 - `test()` to run all tests
		 - `coverage()` to analyse code coverage
		 - `score()` to show coverage score from last run
		 - `clear_coverage_files()` to remove `*.cov` files
		Keep the session alive; changes will be revised and successive runs will be faster.
		"""
	!isinteractive() && test()
elseif "--code-coverage" in ARGS
	coverage()
else
	test(ARGS...)
end
