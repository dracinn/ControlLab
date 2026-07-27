// Exports focused, read-only firmware-updater analysis from a Ghidra project.
// @category ControlLab

import java.io.File;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.data.DataType;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;
import ghidra.program.util.DefinedDataIterator;

public class ExportFirmwareAnalysis extends GhidraScript {
	private static final List<String> TARGETS = Arrays.asList(
		"SwitchUsb",
		"DownloadAllinoneBin",
		"OpenUsb",
		"SetChipType",
		"SetHandshakeTimeout",
		"SetPerPacketSize",
		"ParseNormalFwpkg",
		"ParseNewFwpkg",
		"ParseFile",
		"SendShakeHand",
		"ShakeHand",
		"InitShakeHandCmd",
		"SendFrame",
		"ReceiveFrame",
		"CheckRecvData",
		"GetDouble5CFrameData",
		"WaitSsbRunning",
		"DownloadBootData",
		"FsbWritePage",
		"SendSsbData",
		"SendShaData",
		"SendExitFrame",
		"EraseSsb",
		"DownloadToFlash",
		"EraseAllFlash",
		"BootDownload",
		"UploadFile",
		"InitBeforeBurn",
		"InitLinkPro",
		"OpenUsbDevice",
		"OpenUsbByNum",
		"OpenUsbNoNum",
		"ClaimInterface",
		"GetEPOut",
		"IsCurDevice",
		"CalculateCrc",
		"SopCrc16",
		"TypeSixSerCusPro::WriteBinHead",
		"TypeSixSerCusPro::SendData",
		"TypeSixSerCusPro::StartFlashing",
		"TypeSixSerCusPro::EndFlashingPage",
		"TypeSixSerCusPro::Init",
		"TypeSixSerCusPro::SetSpeed",
		"TypeSixSerCusPro::Reset",
		"TypeSixSerCusPro::EraseCore",
		"TypeSixSerCusPro::InitDataRequestFrame",
		"TypeSixSerCusPro::ParseRecvDataAndWriteFile",
		"FUN_00490b58",
		"FUN_0048ae62",
		"FUN_00498968"
	);

	private static final List<String> STRING_TERMS = Arrays.asList(
		"handshake",
		"shake hand",
		"ack",
		"retry",
		"timeout",
		"crc",
		"erase",
		"download",
		"fwpkg",
		"libusb"
	);

	private static final List<String> IMPORT_TARGETS = Arrays.asList(
		"AES_cbc_encrypt",
		"AES_set_decrypt_key"
	);

	@Override
	public void run() throws Exception {
		String[] arguments = getScriptArgs();
		if (arguments.length != 1) {
			throw new IllegalArgumentException(
				"Expected one argument: an existing output directory");
		}

		File outputDirectory = new File(arguments[0]);
		if (!outputDirectory.isDirectory()) {
			throw new IllegalArgumentException(
				"Output directory does not exist: " + outputDirectory);
		}

		String stem = sanitize(currentProgram.getName());
		exportFunctions(new File(outputDirectory, stem + "-functions.tsv"));
		exportInterestingStrings(new File(outputDirectory, stem + "-strings.tsv"));
		exportTargets(new File(outputDirectory, stem + "-targets.txt"));
	}

	private void exportFunctions(File output) throws Exception {
		try (PrintWriter writer = new PrintWriter(output, "UTF-8")) {
			writer.println("entry\tname\tnamespace\tsize\tsignature");
			FunctionIterator functions =
				currentProgram.getFunctionManager().getFunctions(true);
			while (functions.hasNext() && !monitor.isCancelled()) {
				Function function = functions.next();
				writer.printf(
					"%s\t%s\t%s\t%d\t%s%n",
					function.getEntryPoint(),
					tabSafe(function.getName()),
					tabSafe(function.getParentNamespace().getName(true)),
					function.getBody().getNumAddresses(),
					tabSafe(function.getSignature().getPrototypeString()));
			}
		}
	}

	private void exportInterestingStrings(File output) throws Exception {
		try (PrintWriter writer = new PrintWriter(output, "UTF-8")) {
			writer.println("address\tdatatype\tvalue\treferences");
			for (Data data :
				DefinedDataIterator.byDataInstance(currentProgram, Data::hasStringValue)) {
				if (monitor.isCancelled()) {
					break;
				}
				String value = String.valueOf(data.getValue());
				String lower = value.toLowerCase();
				boolean interesting = STRING_TERMS.stream().anyMatch(lower::contains);
				if (!interesting) {
					continue;
				}
				DataType type = data.getDataType();
				writer.printf(
					"%s\t%s\t%s\t%s%n",
					data.getAddress(),
					tabSafe(type.getDisplayName()),
					tabSafe(value),
					tabSafe(referenceSummary(data.getAddress())));
			}
		}
	}

	private void exportTargets(File output) throws Exception {
		Set<Function> matchSet = new LinkedHashSet<>();
		FunctionIterator functions =
			currentProgram.getFunctionManager().getFunctions(true);
		while (functions.hasNext()) {
			Function function = functions.next();
			String qualifiedName = function.getName(true);
			if (TARGETS.stream().anyMatch(qualifiedName::contains)) {
				matchSet.add(function);
			}
		}
		for (String importName : IMPORT_TARGETS) {
			addImportCallers(matchSet, importName);
		}
		List<Function> matches = new ArrayList<>(matchSet);
		matches.sort(Comparator.comparing(Function::getEntryPoint));

		DecompInterface decompiler = new DecompInterface();
		decompiler.toggleCCode(true);
		decompiler.toggleSyntaxTree(true);
		if (!decompiler.openProgram(currentProgram)) {
			throw new IllegalStateException("Decompiler could not open current program");
		}

		try (PrintWriter writer = new PrintWriter(output, "UTF-8")) {
			writer.println("Program: " + currentProgram.getName());
			writer.println("Executable SHA-256: " +
				currentProgram.getExecutableSHA256());
			writer.println();

			for (Function function : matches) {
				if (monitor.isCancelled()) {
					break;
				}
				writer.println("============================================================");
				writer.println(function.getName(true) + " @ " +
					function.getEntryPoint());
				writer.println("Signature: " +
					function.getSignature().getPrototypeString());
				writer.println("Callers: " + referenceSummary(function.getEntryPoint()));
				writer.println("Callees: " + calleeSummary(function));
				writer.println();

				DecompileResults result =
					decompiler.decompileFunction(function, 120, monitor);
				if (!result.decompileCompleted()) {
					writer.println("[decompilation failed] " +
						result.getErrorMessage());
				}
				else {
					writer.println(
						result.getDecompiledFunction().getC());
				}
				writer.println();
			}
		}
		finally {
			decompiler.dispose();
		}
	}

	private void addImportCallers(Set<Function> matches, String importName) {
		SymbolIterator symbols =
			currentProgram.getSymbolTable().getSymbols(importName);
		while (symbols.hasNext()) {
			Symbol symbol = symbols.next();
			ReferenceIterator references =
				currentProgram.getReferenceManager().getReferencesTo(symbol.getAddress());
			while (references.hasNext()) {
				Reference reference = references.next();
				Function caller = currentProgram.getFunctionManager()
					.getFunctionContaining(reference.getFromAddress());
				if (caller != null) {
					matches.add(caller);
					addCallerChain(matches, caller, 3);
				}
			}
		}
	}

	private void addCallerChain(
			Set<Function> matches, Function function, int remainingDepth) {
		if (remainingDepth == 0) {
			return;
		}
		ReferenceIterator references =
			currentProgram.getReferenceManager().getReferencesTo(function.getEntryPoint());
		while (references.hasNext()) {
			Reference reference = references.next();
			Function caller = currentProgram.getFunctionManager()
				.getFunctionContaining(reference.getFromAddress());
			if (caller != null && matches.add(caller)) {
				addCallerChain(matches, caller, remainingDepth - 1);
			}
		}
	}

	private String referenceSummary(ghidra.program.model.address.Address address) {
		Set<String> callers = new LinkedHashSet<>();
		ReferenceIterator references =
			currentProgram.getReferenceManager().getReferencesTo(address);
		while (references.hasNext()) {
			Reference reference = references.next();
			Function caller = currentProgram.getFunctionManager()
				.getFunctionContaining(reference.getFromAddress());
			if (caller == null) {
				callers.add(reference.getFromAddress().toString());
			}
			else {
				callers.add(caller.getName(true) + "@" + caller.getEntryPoint());
			}
		}
		return callers.isEmpty() ? "-" : String.join(", ", callers);
	}

	private String calleeSummary(Function function) {
		Set<String> callees = new LinkedHashSet<>();
		for (Function callee : function.getCalledFunctions(monitor)) {
			callees.add(callee.getName(true) + "@" + callee.getEntryPoint());
		}
		return callees.isEmpty() ? "-" : String.join(", ", callees);
	}

	private String sanitize(String value) {
		return value.replaceAll("[^A-Za-z0-9._-]", "_");
	}

	private String tabSafe(String value) {
		return value.replace('\t', ' ').replace('\r', ' ').replace('\n', ' ');
	}
}
