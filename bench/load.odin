// Load benchmark: `load_graph` + `graph_destroy` over the pinned GrappleMap.txt (phase 2, spec "UX").
// No threshold: the number is reported, not enforced. Run with `./build.sh bench`.
package bench

import "app:core"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"

DB_PATH :: #directory + "../reference/GrappleMap/GrappleMap.txt"
RUNS :: 9 // timed runs after one warm-up; odd, so the median is a sample

main :: proc() {
	data, read_err := os.read_entire_file(DB_PATH, context.allocator)
	if read_err != nil {
		fmt.eprintfln("error: cannot read %s: %s", DB_PATH, os.error_string(read_err))
		fmt.eprintln("run git submodule update --init")
		os.exit(1)
	}
	defer delete(data)

	counts: string
	times: [RUNS]f64
	for run in 0 ..= RUNS {
		start := time.tick_now()
		g, err := core.load_graph(data)
		elapsed := time.tick_since(start)
		if err != nil {
			fmt.eprintfln("error: load_graph: %v", err)
			os.exit(1)
		}
		if run == 0 { 	// warm-up: not timed
			counts = fmt.aprintf(
				"blocks=%d named=%d transitions=%d nodes=%d",
				g.named_count + len(g.edges),
				g.named_count,
				len(g.edges),
				len(g.nodes),
			)
		} else {
			times[run - 1] = time.duration_milliseconds(elapsed)
		}
		core.graph_destroy(&g)
		free_all(context.temp_allocator)
	}
	defer delete(counts)

	slice.sort(times[:])
	fmt.printfln(
		"load_graph: median %.2f ms, min %.2f ms, max %.2f ms (%d runs after 1 warm-up)",
		times[RUNS / 2],
		times[0],
		times[RUNS - 1],
		RUNS,
	)
	fmt.println(counts)
}
