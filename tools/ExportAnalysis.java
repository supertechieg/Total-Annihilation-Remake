// Export function metadata and decompiler output for a local analysis project.
// @category TotalAnnihilation
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import java.io.BufferedWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

public class ExportAnalysis extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 1) throw new IllegalArgumentException("Expected output directory");
        Path output = Path.of(args[0]);
        Files.createDirectories(output);
        DecompInterface decompiler = new DecompInterface();
        if (!decompiler.openProgram(currentProgram)) {
            throw new IllegalStateException(decompiler.getLastMessage());
        }
        int completed = 0;
        int failed = 0;
        try (BufferedWriter code = Files.newBufferedWriter(output.resolve("TotalA.decompiled.c"), StandardCharsets.UTF_8);
             BufferedWriter functions = Files.newBufferedWriter(output.resolve("functions.tsv"), StandardCharsets.UTF_8)) {
            code.write("/* Analysis pseudocode. Not recovered original source or a buildable program. */\n");
            functions.write("address\tname\tbody_bytes\tstatus\n");
            FunctionIterator iterator = currentProgram.getFunctionManager().getFunctions(true);
            while (iterator.hasNext() && !monitor.isCancelled()) {
                Function function = iterator.next();
                if (function.isExternal()) continue;
                DecompileResults result = decompiler.decompileFunction(function, 30, monitor);
                boolean ok = result.decompileCompleted() && result.getDecompiledFunction() != null;
                functions.write(function.getEntryPoint() + "\t" + function.getName() + "\t" +
                    function.getBody().getNumAddresses() + "\t" + (ok ? "ok" : "failed") + "\n");
                code.write("\n/* Address: " + function.getEntryPoint() + " */\n");
                if (ok) {
                    code.write(result.getDecompiledFunction().getC());
                    completed++;
                } else {
                    code.write("/* Decompilation failed; inspect this function in Ghidra. */\n");
                    failed++;
                }
            }
        } finally {
            decompiler.dispose();
        }
        String summary = "decompiled=" + completed + " failed=" + failed + " cancelled=" + monitor.isCancelled();
        Files.writeString(output.resolve("export-status.txt"), summary, StandardCharsets.UTF_8);
        println(summary);
    }
}
