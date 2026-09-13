// Export recognized string literals and their referencing functions.
// @category TotalAnnihilation
import ghidra.app.script.GhidraScript;
import ghidra.program.model.data.StringDataInstance;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import java.io.BufferedWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

public class ExportStringReferences extends GhidraScript {
    private String clean(String value) {
        return value.replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n");
    }
    @Override
    public void run() throws Exception {
        Path output = Path.of(getScriptArgs()[0]);
        Files.createDirectories(output);
        try (BufferedWriter writer = Files.newBufferedWriter(output.resolve("string-references.tsv"), StandardCharsets.UTF_8)) {
            writer.write("string_address\treference_address\tfunction_address\tfunction\ttext\n");
            DataIterator iterator = currentProgram.getListing().getDefinedData(true);
            while (iterator.hasNext() && !monitor.isCancelled()) {
                Data data = iterator.next();
                if (!StringDataInstance.isString(data)) continue;
                String value = StringDataInstance.getStringDataInstance(data).getStringValue();
                if (value == null) continue;
                ReferenceIterator refs = currentProgram.getReferenceManager().getReferencesTo(data.getAddress());
                while (refs.hasNext()) {
                    Reference ref = refs.next();
                    Function function = currentProgram.getFunctionManager().getFunctionContaining(ref.getFromAddress());
                    writer.write(data.getAddress() + "\t" + ref.getFromAddress() + "\t" +
                        (function == null ? "\t" : function.getEntryPoint() + "\t" + function.getName()) +
                        "\t" + clean(value) + "\n");
                }
            }
        }
    }
}
