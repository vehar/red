Red/System [
	Title:   "Red native functions"
	Author:  "Nenad Rakocevic"
	File: 	 %natives.reds
	Tabs:	 4
	Rights:  "Copyright (C) 2011-2015 Nenad Rakocevic. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/red/red/blob/master/BSL-License.txt
	}
]

#define RETURN_NONE [
	stack/reset
	none/push-last
	exit
]

natives: context [
	verbose:  0
	lf?: 	  no										;-- used to print or not an ending newline
	last-lf?: no
	
	table: declare int-ptr!
	top: 1
	
	buffer-blk: as red-block! 0

	register: func [
		[variadic]
		count	   [integer!]
		list	   [int-ptr!]
		/local
			offset [integer!]
	][
		offset: 0
		
		until [
			table/top: list/value
			top: top + 1
			assert top <= NATIVES_NB
			list: list + 1
			count: count - 1
			zero? count
		]
	]
	
	;--- Natives ----
	
	if*: does [
		either logic/false? [
			RETURN_NONE
		][
			interpreter/eval as red-block! stack/arguments + 1 yes
		]
	]
	
	unless*: does [
		either logic/false? [
			interpreter/eval as red-block! stack/arguments + 1 yes
		][
			RETURN_NONE
		]
	]
	
	either*: func [
		/local offset [integer!]
	][
		offset: either logic/true? [1][2]
		interpreter/eval as red-block! stack/arguments + offset yes
	]
	
	any*: func [
		/local
			value [red-value!]
			tail  [red-value!]
	][
		value: block/rs-head as red-block! stack/arguments
		tail:  block/rs-tail as red-block! stack/arguments
		
		while [value < tail][
			value: interpreter/eval-next value tail no
			if logic/true? [exit]
		]
		RETURN_NONE
	]
	
	all*: func [
		/local
			value [red-value!]
			tail  [red-value!]
	][
		value: block/rs-head as red-block! stack/arguments
		tail:  block/rs-tail as red-block! stack/arguments
		
		if value = tail [RETURN_NONE]
		
		while [value < tail][
			value: interpreter/eval-next value tail no
			if logic/false? [RETURN_NONE]
		]
	]
	
	while*:	func [
		/local
			cond  [red-block!]
			body  [red-block!]
	][
		cond: as red-block! stack/arguments
		body: as red-block! stack/arguments + 1
		
		stack/mark-loop words/_body
		while [
			interpreter/eval cond yes
			logic/true?
		][
			stack/reset
			catch RED_THROWN_BREAK [interpreter/eval body yes]
			switch system/thrown [
				RED_THROWN_BREAK	[system/thrown: 0 break]
				RED_THROWN_CONTINUE	[system/thrown: 0 continue]
				0 					[0]
				default				[re-throw]
			]
		]
		stack/unwind
		stack/reset
		unset/push-last
	]
	
	until*: func [
		/local
			body  [red-block!]
	][
		body: as red-block! stack/arguments

		stack/mark-loop words/_body
		until [
			stack/reset
			catch RED_THROWN_BREAK	[interpreter/eval body yes]
			switch system/thrown [
				RED_THROWN_BREAK	[system/thrown: 0 break]
				RED_THROWN_CONTINUE	[system/thrown: 0 continue]
				0 					[0]
				default				[re-throw]
			]
			logic/true?
		]
		stack/unwind-last
	]
	
	loop*: func [
		[catch]
		/local
			body  [red-block!]
			count [integer!]
			id 	  [integer!]
			saved [int-ptr!]
	][
		count: integer/get*
		unless positive? count [RETURN_NONE]			;-- if counter <= 0, no loops
		body: as red-block! stack/arguments + 1
		
		stack/mark-loop words/_body		
		loop count [
			stack/reset
			saved: system/stack/top						;--	FIXME: solve loop/catch conflict
			interpreter/eval body yes
			system/stack/top: saved
			
			switch system/thrown [
				RED_THROWN_BREAK	[system/thrown: 0 break]
				RED_THROWN_CONTINUE	[system/thrown: 0 continue]
				0 					[0]
				default				[id: system/thrown throw id]
			]
		]
		stack/unwind-last
	]
	
	repeat*: func [
		/local
			w	   [red-word!]
			body   [red-block!]
			count  [red-integer!]
			cnt	   [integer!]
			i	   [integer!]
	][
		w: 	   as red-word!    stack/arguments
		count: as red-integer! stack/arguments + 1
		body:  as red-block!   stack/arguments + 2
		
		i: integer/get as red-value! count
		unless positive? i [RETURN_NONE]				;-- if counter <= 0, no loops
		
		count/value: 1
	
		stack/mark-loop words/_body
		until [
			stack/reset
			_context/set w as red-value! count
			catch RED_THROWN_BREAK [interpreter/eval body yes]
			switch system/thrown [
				RED_THROWN_BREAK [system/thrown: 0 break]
				RED_THROWN_CONTINUE
				0 [
					system/thrown: 0
					count/value: count/value + 1
					i: i - 1
				]
				default	[re-throw]
			]
			zero? i
		]
		stack/unwind-last
	]
	
	forever*: func [
		/local
			body  [red-block!]
	][
		body: as red-block! stack/arguments
		
		stack/mark-loop words/_body
		forever [
			catch RED_THROWN_BREAK	[interpreter/eval body no]
			switch system/thrown [
				RED_THROWN_BREAK	[system/thrown: 0 break]
				RED_THROWN_CONTINUE	[system/thrown: 0 continue]
				0 					[stack/pop 1]
				default				[re-throw]
			]
		]
		stack/unwind-last
	]
	
	foreach*: func [
		/local
			value [red-value!]
			body  [red-block!]
			size  [integer!]
	][
		value: stack/arguments
		body: as red-block! stack/arguments + 2
		
		stack/push stack/arguments + 1					;-- copy arguments to stack top in reverse order
		stack/push value								;-- (required by foreach-next)
		
		stack/mark-loop words/_body
		stack/set-last unset-value
		
		either TYPE_OF(value) = TYPE_BLOCK [
			size: block/rs-length? as red-block! value
			
			while [foreach-next-block size][			;-- foreach [..]
				stack/reset
				catch RED_THROWN_BREAK	[interpreter/eval body no]
				switch system/thrown [
					RED_THROWN_BREAK	[system/thrown: 0 break]
					RED_THROWN_CONTINUE	[system/thrown: 0 continue]
					0 					[0]
					default				[re-throw]
				]
			]
		][
			while [foreach-next][						;-- foreach <word!>
				stack/reset
				catch RED_THROWN_BREAK	[interpreter/eval body no]
				switch system/thrown [
					RED_THROWN_BREAK	[system/thrown: 0 break]
					RED_THROWN_CONTINUE	[system/thrown: 0 continue]
					0 					[0]
					default				[re-throw]
				]
			]
		]
		stack/unwind-last
	]
	
	forall*: func [
		/local
			w 	   [red-word!]
			body   [red-block!]
			saved  [red-value!]
			series [red-series!]
	][
		w:    as red-word!  stack/arguments
		body: as red-block! stack/arguments + 1
		
		saved: word/get w							;-- save series (for resetting on end)
		w: word/push w								;-- word argument
		
		stack/mark-loop words/_body
		while [loop? as red-series! _context/get w][
			stack/reset
			catch RED_THROWN_BREAK	[interpreter/eval body no]
			switch system/thrown [
				RED_THROWN_BREAK	[system/thrown: 0 break]
				RED_THROWN_CONTINUE	[system/thrown: 0 continue]
				0 [
					series: as red-series! _context/get w
					series/head: series/head + 1
				]
				default	[re-throw]
			]
		]
		stack/unwind-last
		_context/set w saved
	]
	
	func*: does [
		_function/validate as red-block! stack/arguments
		_function/push 
			as red-block! stack/arguments
			as red-block! stack/arguments + 1
			null
			0
			null
		stack/set-last stack/top - 1
	]
	
	function*:	does [
		_function/collect-words
			as red-block! stack/arguments
			as red-block! stack/arguments + 1
		func*
	]
	
	does*: does [
		copy-cell stack/arguments stack/push*
		block/make-at as red-block! stack/arguments 1
		func*
	]
	
	has*: func [/local blk [red-block!]][
		blk: as red-block! stack/arguments
		block/insert-value blk as red-value! refinements/local
		blk/head: blk/head - 1
		func*
	]
		
	switch*: func [
		default? [integer!]
		/local
			pos	 [red-value!]
			blk  [red-block!]
			alt  [red-block!]
			end  [red-value!]
			s	 [series!]
	][
		blk: as red-block! stack/arguments + 1
		alt: as red-block! stack/arguments + 2
		
		pos: actions/find
			as red-series! blk
			stack/arguments
			null
			yes											;-- /only
			no
			no
			null
			null
			no
			no
			yes											;-- /tail
			no
			
		either TYPE_OF(pos) = TYPE_NONE [
			either negative? default? [
				RETURN_NONE
			][
				interpreter/eval alt yes
				exit									;-- early exit with last value on stack
			]
		][
			s: GET_BUFFER(blk)
			end: s/tail
			pos: _series/pick as red-series! pos 1 null
			
			while [pos < end][							;-- find first following block
				if TYPE_OF(pos) = TYPE_BLOCK [
					stack/reset
					interpreter/eval as red-block! pos yes	;-- do the block
					exit								;-- early exit with last value on stack
				]
				pos: pos + 1
			]
		]
		RETURN_NONE
	]
	
	case*: func [
		all? 	  [integer!]
		/local
			value [red-value!]
			tail  [red-value!]
	][
		value: block/rs-head as red-block! stack/arguments
		tail:  block/rs-tail as red-block! stack/arguments
		if value = tail [RETURN_NONE]
		
		while [value < tail][
			value: interpreter/eval-next value tail no	;-- eval condition
			if value = tail [break]
			either logic/true? [
				either TYPE_OF(value) = TYPE_BLOCK [	;-- if true, eval what follows it
					stack/reset
					interpreter/eval as red-block! value yes
					value: value + 1
				][
					value: interpreter/eval-next value tail no
				]
				if negative? all? [exit]				;-- early exit with last value on stack (unless /all)
			][
				value: value + 1						;-- single value only allowed for cases bodies
			]
		]
		RETURN_NONE
	]
	
	do*: func [
		return: [integer!]
		/local
			cframe [byte-ptr!]
			arg	   [red-value!]
			str	   [red-string!]
			s	   [series!]
			out    [red-string!]
			len	   [integer!]
	][
		arg: stack/arguments
		cframe: stack/get-ctop							;-- save the current call frame pointer
		
		catch RED_THROWN_BREAK [
			switch TYPE_OF(arg) [
				TYPE_BLOCK [
					interpreter/eval as red-block! arg yes
				]
				TYPE_PATH [
					interpreter/eval-path arg arg arg + 1 no no no no
					stack/set-last arg + 1
				]
				TYPE_STRING [
					str: as red-string! arg
					#call [system/lexer/transcode str none]
					interpreter/eval as red-block! arg yes
				]
				TYPE_FILE [
					len: -1
					str: as red-string! arg
					out: string/rs-make-at stack/push* string/rs-length? str
					file/to-local-path as red-file! str out false
					str: simple-io/read-txt unicode/to-utf8 out :len
					#call [system/lexer/transcode str none]
					interpreter/eval as red-block! arg yes
				]
				TYPE_ERROR [
					stack/throw-error as red-object! arg
				]
				default [
					interpreter/eval-expression arg arg + 1 no no
				]
			]
		]
		switch system/thrown [
			RED_THROWN_BREAK
			RED_THROWN_CONTINUE
			RED_THROWN_RETURN
			RED_THROWN_EXIT [
				either stack/eval? cframe [				;-- if run from interpreter,
					re-throw 							;-- let the exception pass through
					0									;-- 0 to make compiler happy		
				][
					system/thrown						;-- request an early exit from caller
				]
			]
			0			[0]
			default 	[re-throw 0]					;-- 0 to make compiler happy
		]
	]
	
	get*: func [
		any?  [integer!]
		case? [integer!]
		/local
			value [red-value!]
			type  [integer!]
	][
		value: stack/arguments
		type: TYPE_OF(value)
		
		switch type [
			TYPE_PATH
			TYPE_GET_PATH
			TYPE_SET_PATH
			TYPE_LIT_PATH [
				interpreter/eval-path value null null no yes no case? <> -1
			]
			TYPE_OBJECT [
				object/reflect as red-object! value words/values
			]
			default [
				stack/set-last _context/get as red-word! stack/arguments
			]
		]
	]
	
	set*: func [
		any?  [integer!]
		case? [integer!]
		/local
			w	  [red-word!]
			value [red-value!]
			blk	  [red-block!]
	][
		w: as red-word! stack/arguments
		value: stack/arguments + 1
		
		switch TYPE_OF(w) [
			TYPE_PATH
			TYPE_GET_PATH
			TYPE_SET_PATH
			TYPE_LIT_PATH [
				value: stack/push stack/arguments
				copy-cell stack/arguments + 1 stack/arguments
				interpreter/eval-path value null null yes no no case? <> -1
			]
			TYPE_OBJECT [
				set-obj-many as red-object! w value
				stack/set-last value
			]
			TYPE_MAP [
				map/set-many as red-hash! w as red-block! value
				stack/set-last value
			]
			TYPE_BLOCK [
				blk: as red-block! w
				set-many blk value block/rs-length? blk
				stack/set-last value
			]
			default [
				stack/set-last _context/set w value
			]
		]
	]

	print*: does [
		lf?: yes											;@@ get rid of this global state
		prin*
		lf?: no
		last-lf?: yes
	]
	
	prin*: func [
		/local
			arg		[red-value!]
			str		[red-string!]
			blk		[red-block!]
			series	[series!]
			offset	[byte-ptr!]
			size	[integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/prin"]]
		
		arg: stack/arguments

		if TYPE_OF(arg) = TYPE_BLOCK [
			block/rs-clear buffer-blk
			stack/push as red-value! buffer-blk
			assert stack/top - 2 = stack/arguments			;-- check for correct stack layout
			reduce* 1
			blk: as red-block! arg
			blk/head: 0										;-- head changed by reduce/into
		]

		actions/form* -1
		str: as red-string! stack/arguments
		assert any [
			TYPE_OF(str) = TYPE_STRING
			TYPE_OF(str) = TYPE_SYMBOL						;-- symbol! and string! structs are overlapping
		]
		series: GET_BUFFER(str)
		offset: (as byte-ptr! series/offset) + (str/head << (log-b GET_UNIT(series)))
		size: as-integer (as byte-ptr! series/tail) - offset

		either lf? [
			switch GET_UNIT(series) [
				Latin1 [platform/print-line-Latin1 as c-string! offset size]
				UCS-2  [platform/print-line-UCS2 				offset size]
				UCS-4  [platform/print-line-UCS4   as int-ptr!  offset size]

				default [									;@@ replace by an assertion
					print-line ["Error: unknown string encoding: " GET_UNIT(series)]
				]
			]
		][
			switch GET_UNIT(series) [
				Latin1 [platform/print-Latin1 as c-string! offset size]
				UCS-2  [platform/print-UCS2   			   offset size]
				UCS-4  [platform/print-UCS4   as int-ptr!  offset size]

				default [									;@@ replace by an assertion
					print-line ["Error: unknown string encoding: " GET_UNIT(series)]
				]
			]
		]
		last-lf?: no
		stack/set-last unset-value
	]
	
	equal?*: func [
		return:    [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/equal?"]]
		actions/compare* COMP_EQUAL
	]
	
	not-equal?*: func [
		return:    [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/not-equal?"]]
		actions/compare* COMP_NOT_EQUAL
	]
	
	strict-equal?*: func [
		return:    [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/strict-equal?"]]
		actions/compare* COMP_STRICT_EQUAL
	]
	
	lesser?*: func [
		return:    [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/lesser?"]]
		actions/compare* COMP_LESSER
	]
	
	greater?*: func [
		return:    [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/greater?"]]
		actions/compare* COMP_GREATER
	]
	
	lesser-or-equal?*: func [
		return:    [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/lesser-or-equal?"]]
		actions/compare* COMP_LESSER_EQUAL
	]	
	
	greater-or-equal?*: func [
		return:    [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/greater-or-equal?"]]
		actions/compare* COMP_GREATER_EQUAL
	]
	
	same?*: func [
		return:	   [red-logic!]
		/local
			result [red-logic!]
			arg1   [red-value!]
			arg2   [red-value!]
			type   [integer!]
			res    [logic!]
	][
		arg1: stack/arguments
		arg2: arg1 + 1
		type: TYPE_OF(arg1)

		res: false
		if type = TYPE_OF(arg2) [
			case [
				any [
					type = TYPE_DATATYPE
					type = TYPE_LOGIC
					type = TYPE_OBJECT
				][
					res: arg1/data1 = arg2/data1
				]
				any [
					type = TYPE_CHAR
					type = TYPE_INTEGER
					type = TYPE_BITSET
				][
					res: arg1/data2 = arg2/data2
				]
				ANY_SERIES?(type) [
					res: all [arg1/data1 = arg2/data1 arg1/data2 = arg2/data2]
				]
				type = TYPE_FLOAT	[
					res: all [arg1/data2 = arg2/data2 arg1/data3 = arg2/data3]
				]
				type = TYPE_NONE	[type = TYPE_OF(arg2)]
				true [
					res: all [
						arg1/data1 = arg2/data1
						arg1/data2 = arg2/data2
						arg1/data3 = arg2/data3
					]
				]
			]
		]

		result: as red-logic! arg1
		result/value: res
		result/header: TYPE_LOGIC
		result
	]

	not*: func [
		/local bool [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/not"]]
		
		bool: as red-logic! stack/arguments
		bool/value: logic/false?						;-- run test before modifying stack
		bool/header: TYPE_LOGIC
	]
	
	halt*: does [halt]
	
	type?*: func [
		word?	 [integer!]
		return:  [red-value!]
		/local
			dt	 [red-datatype!]
			w	 [red-word!]
			name [names!]
	][
		either negative? word? [
			dt: as red-datatype! stack/arguments		;-- overwrite argument
			dt/value: TYPE_OF(dt)						;-- extract type before overriding
			dt/header: TYPE_DATATYPE
			as red-value! dt
		][
			w: as red-word! stack/arguments				;-- overwrite argument
			name: name-table + TYPE_OF(w)				;-- point to the right datatype name record
			stack/set-last as red-value! name/word
		]
	]
	
	reduce*: func [
		into [integer!]
		/local
			value [red-value!]
			tail  [red-value!]
			arg	  [red-value!]
			into? [logic!]
			blk?  [logic!]
	][
		arg: stack/arguments
		blk?: TYPE_OF(arg) = TYPE_BLOCK
		into?: into >= 0

		if blk? [
			value: block/rs-head as red-block! arg
			tail:  block/rs-tail as red-block! arg
		]

		stack/mark-native words/_body

		either into? [
			as red-block! stack/push arg + into
		][
			if blk? [block/push-only* (as-integer tail - value) >> 4]
		]

		either blk? [
			while [value < tail][
				value: interpreter/eval-next value tail yes
				either into? [actions/insert* -1 0 -1][block/append*]
				stack/keep									;-- preserve the reduced block on stack
			]
		][
			interpreter/eval-expression arg arg + 1 no yes	;-- for non block! values
			if into? [actions/insert* -1 0 -1]
		]
		stack/unwind-last
	]
	
	compose-block: func [
		blk		[red-block!]
		deep?	[logic!]
		only?	[logic!]
		into	[red-block!]
		root?	[logic!]
		return: [red-block!]
		/local
			value  [red-value!]
			tail   [red-value!]
			new	   [red-block!]
			result [red-value!]
			into?  [logic!]
	][
		value: block/rs-head blk
		tail:  block/rs-tail blk
		into?: all [root? OPTION?(into)]

		new: either into? [
			into
		][
			block/push-only* (as-integer tail - value) >> 4	
		]
		while [value < tail][
			switch TYPE_OF(value) [
				TYPE_BLOCK [
					blk: either deep? [
						compose-block as red-block! value deep? only? into no
					][
						as red-block! value
					]
					either into? [
						block/insert-value new as red-value! blk
					][
						copy-cell as red-value! blk ALLOC_TAIL(new)
					]
				]
				TYPE_PAREN [
					blk: as red-block! value
					unless zero? block/rs-length? blk [
						interpreter/eval blk yes
						result: stack/arguments
						blk: as red-block! result 
						
						unless any [
							TYPE_OF(result) = TYPE_UNSET
							all [
								not only?
								TYPE_OF(result) = TYPE_BLOCK
								zero? block/rs-length? blk
							]
						][
							either any [
								only? 
								TYPE_OF(result) <> TYPE_BLOCK
							][
								either into? [
									block/insert-value new result
								][
									copy-cell result ALLOC_TAIL(new)
								]
							][
								either into? [
									block/insert-block new as red-block! result
								][
									block/rs-append-block new as red-block! result
								]
							]
						]
					]
				]
				default [
					either into? [
						block/insert-value new value
					][
						copy-cell value ALLOC_TAIL(new)
					]
				]
			]
			value: value + 1
		]
		new
	]
	
	compose*: func [
		deep [integer!]
		only [integer!]
		into [integer!]
		/local
			into? [logic!]
	][
		arg: stack/arguments
		either TYPE_OF(arg) <> TYPE_BLOCK [					;-- pass-thru for non block! values
			into?: into >= 0
			stack/mark-native words/_body
			if into? [as red-block! stack/push arg + into]
			interpreter/eval-expression arg arg + 1 no yes
			if into? [actions/insert* -1 0 -1]
			stack/unwind-last
		][
			stack/set-last
				as red-value! compose-block
					as red-block! arg
					as logic! deep + 1
					as logic! only + 1
					as red-block! stack/arguments + into
					yes
		]
	]
	
	stats*: func [
		show [integer!]
		info [integer!]
		/local
			blk [red-block!]
	][
		case [
			show >= 0 [
				;TBD
				integer/box memory/total
			]
			info >= 0 [
				blk: block/push* 5
				memory-info blk 2
				stack/set-last as red-value! blk
			]
			true [
				integer/box memory/total
			]
		]
	]
	
	bind*: func [
		copy [integer!]
		/local
			value [red-value!]
			ref	  [red-value!]
			fun	  [red-function!]
			word  [red-word!]
			ctx	  [node!]
	][
		value: stack/arguments
		ref: value + 1
		
		either any [
			TYPE_OF(ref) = TYPE_FUNCTION
			;TYPE_OF(ref) = TYPE_OBJECT
		][
			fun: as red-function! ref
			ctx: fun/ctx
		][
			word: as red-word! ref
			ctx: word/ctx
		]
		
		either TYPE_OF(value) = TYPE_BLOCK [
			either negative? copy [
				_context/bind as red-block! value TO_CTX(ctx) null no
			][
				stack/set-last 
					as red-value! _context/bind
						block/clone as red-block! value yes no
						TO_CTX(ctx)
						null
						no
			]
		][
			word: as red-word! value
			word/ctx: ctx
			word/index: _context/find-word TO_CTX(ctx) word/symbol no
		]
	]
	
	in*: func [
		/local
			obj  [red-object!]
			ctx  [red-context!]
			word [red-word!]
	][
		obj:  as red-object! stack/arguments
		word: as red-word! stack/arguments + 1
		ctx: GET_CTX(obj)

		switch TYPE_OF(word) [
			TYPE_WORD
			TYPE_GET_WORD
			TYPE_SET_WORD
			TYPE_LIT_WORD
			TYPE_REFINEMENT [
				stack/set-last as red-value!
				either negative? _context/bind-word ctx word [
					none-value
				][
					word
				]
			]
			TYPE_BLOCK
			TYPE_PAREN [
				0
			]
			default [0]
		]
	]

	parse*: func [
		case?	[integer!]
		;strict? [integer!]
		part	[integer!]
		trace	[integer!]
		return: [integer!]
		/local
			op	   [integer!]
			input  [red-series!]
			limit  [red-series!]
			int	   [red-integer!]
			res	   [red-value!]
			cframe [byte-ptr!]
	][
		op: either as logic! case? + 1 [COMP_STRICT_EQUAL][COMP_EQUAL]
		
		input: as red-series! stack/arguments
		limit: as red-series! stack/arguments + part
		part: 0
		
		if OPTION?(limit) [
			part: either TYPE_OF(limit) = TYPE_INTEGER [
				int: as red-integer! limit
				int/value + input/head
			][
				unless all [
					TYPE_OF(limit) = TYPE_OF(input)
					limit/node = input/node
				][
					ERR_INVALID_REFINEMENT_ARG(refinements/_part limit)
				]
				limit/head
			]
			if part <= 0 [
				logic/box zero? either any [
					TYPE_OF(input) = TYPE_STRING		;@@ replace with ANY_STRING?
					TYPE_OF(input) = TYPE_FILE
					TYPE_OF(input) = TYPE_URL
				][
					string/rs-length? as red-string! input
				][
					block/rs-length? as red-block! input
				]
				return 0
			]
		]
		cframe: stack/get-ctop							;-- save the current call frame pointer
		
		catch RED_THROWN_BREAK [
			res: parser/process
				input
				as red-block! stack/arguments + 1
				op
				;as logic! strict? + 1
				part
				as red-function! stack/arguments + trace
		]
		switch system/thrown [
			RED_THROWN_BREAK
			RED_THROWN_CONTINUE
			RED_THROWN_RETURN
			RED_THROWN_EXIT [
				either stack/eval? cframe [				;-- if run from interpreter,
					re-throw 							;-- let the exception pass through
					0									;-- 0 to make compiler happy		
				][
					system/thrown						;-- request an early exit from caller
				]
			]
			0			[stack/set-last res 0]			;-- 0 to make compiler happy
			default 	[re-throw 0]					;-- 0 to make compiler happy
		]
	]

	do-set-op*: func [
		cased	 [integer!]
		skip	 [integer!]
		op		 [integer!]
		/local
			set1	 [red-value!]
			skip-arg [red-value!]
			case?	 [logic!]
	][
		set1:	  stack/arguments
		skip-arg: set1 + skip
		case?:	  as logic! cased + 1
		
		switch TYPE_OF(set1) [
			TYPE_BLOCK   
			TYPE_HASH    [block/do-set-op case? as red-integer! skip-arg op]
			TYPE_STRING  [string/do-set-op case? as red-integer! skip-arg op]
			TYPE_BITSET  [bitset/do-bitwise op]
			TYPE_TYPESET [typeset/do-bitwise op]
			default 	 [ERR_EXPECT_ARGUMENT((TYPE_OF(set1)) 1)]
		]
	]
	
	union*: func [
		cased	 [integer!]
		skip	 [integer!]
	][
		do-set-op* cased skip OP_UNION
	]
	
	intersect*: func [
		cased	 [integer!]
		skip	 [integer!]
	][
		do-set-op* cased skip OP_INTERSECT
	]
	
	unique*: func [
		cased	 [integer!]
		skip	 [integer!]
	][
		do-set-op* cased skip OP_UNIQUE
	]
	
	difference*: func [
		cased	 [integer!]
		skip	 [integer!]
	][
		do-set-op* cased skip OP_DIFFERENCE
	]

	exclude*: func [
		cased	 [integer!]
		skip	 [integer!]
	][
		do-set-op* cased skip OP_EXCLUDE
	]

	complement?*: func [
		return:    [red-logic!]
		/local
			bits   [red-bitset!]
			s	   [series!]
			result [red-logic!]
	][
		bits: as red-bitset! stack/arguments
		s: GET_BUFFER(bits)
		result: as red-logic! bits

		either TYPE_OF(bits) =  TYPE_BITSET [
			result/value: s/flags and flag-bitset-not = flag-bitset-not
		][
			ERR_EXPECT_ARGUMENT((TYPE_OF(bits)) 1)
		]

		result/header: TYPE_LOGIC
		result
	]

	dehex*: func [
		return:		[red-string!]
		/local
			str		[red-string!]
			buffer	[red-string!]
			s		[series!]
			p		[byte-ptr!]
			p4		[int-ptr!]
			tail	[byte-ptr!]
			unit	[integer!]
			cp		[integer!]
			len		[integer!]
	][
		str: as red-string! stack/arguments
		s: GET_BUFFER(str)
		unit: GET_UNIT(s)
		p: (as byte-ptr! s/offset) + (str/head << (log-b unit))
		tail: as byte-ptr! s/tail
		if p = tail [return str]						;-- empty string case

		len: string/rs-length? str
		stack/keep										;-- keep last value
		buffer: string/rs-make-at stack/push* len * unit

		while [p < tail][
			cp: switch unit [
				Latin1 [as-integer p/value]
				UCS-2  [(as-integer p/2) << 8 + p/1]
				UCS-4  [p4: as int-ptr! p p4/value]
			]

			p: p + unit
			if all [
				cp = as-integer #"%"
				p + (unit << 1) < tail					;-- must be %xx
			][
				p: string/decode-utf8-hex p unit :cp false
			]
			string/append-char GET_BUFFER(buffer) cp unit
		]
		stack/set-last as red-value! buffer
		buffer
	]

	negative?*: func [
		return:	[red-logic!]
		/local
			num [red-integer!]
			f	[red-float!]
			res [red-logic!]
	][
		res: as red-logic! stack/arguments
		switch TYPE_OF(res) [						;@@ Add time! money! pair!
			TYPE_INTEGER [
				num: as red-integer! res
				res/value: negative? num/value
			]
			TYPE_FLOAT	 [
				f: as red-float! res
				res/value: f/value < 0.0
			]
			default [ERR_EXPECT_ARGUMENT((TYPE_OF(res)) 1)]
		]
		res/header: TYPE_LOGIC
		res
	]

	positive?*: func [
		return: [red-logic!]
		/local
			num [red-integer!]
			f	[red-float!]
			res [red-logic!]
	][
		res: as red-logic! stack/arguments
		switch TYPE_OF(res) [						;@@ Add time! money! pair!
			TYPE_INTEGER [
				num: as red-integer! res
				res/value: positive? num/value
			]
			TYPE_FLOAT	 [
				f: as red-float! res
				res/value: f/value > 0.0
			]
			default [ERR_EXPECT_ARGUMENT((TYPE_OF(res)) 1)]
		]
		res/header: TYPE_LOGIC
		res
	]

	max*: func [
		/local
			args	[red-value!]
			result	[logic!]
	][
		args: stack/arguments
		result: actions/compare args args + 1 COMP_LESSER
		if result [
			stack/set-last args + 1
		]
	]

	min*: func [
		/local
			args	[red-value!]
			result	[logic!]
	][
		args: stack/arguments
		result: actions/compare args args + 1 COMP_LESSER
		unless result [
			stack/set-last args + 1
		]
	]

	shift*: func [
		left	 [integer!]
		logical  [integer!]
		/local
			data [red-integer!]
			bits [red-integer!]
	][
		data: as red-integer! stack/arguments
		bits: data + 1
		case [
			left >= 0 [
				data/value: data/value << bits/value
			]
			logical >= 0 [
				data/value: data/value >>> bits/value
			]
			true [
				data/value: data/value >> bits/value
			]
		]
	]

	to-hex*: func [
		size	  [integer!]
		/local
			arg	  [red-integer!]
			limit [red-integer!]
			buf   [red-word!]
			p	  [c-string!]
			part  [integer!]
	][
		arg: as red-integer! stack/arguments
		limit: arg + size

		p: string/to-hex arg/value no
		part: either OPTION?(limit) [8 - limit/value][0]
		if negative? part [part: 0]
		buf: issue/load p + part

		stack/set-last as red-value! buf
	]

	sine*: func [
		radians [integer!]
		/local
			f	[red-float!]
	][
		f: degree-to-radians radians SINE
		f/value: sin f/value
		if DBL_EPSILON > float/abs f/value [f/value: 0.0]
		f
	]

	cosine*: func [
		radians [integer!]
		/local
			f	[red-float!]
	][
		f: degree-to-radians radians COSINE
		f/value: cos f/value
		if DBL_EPSILON > float/abs f/value [f/value: 0.0]
		f
	]

	tangent*: func [
		radians [integer!]
		/local
			f	[red-float!]
	][
		f: degree-to-radians radians TANGENT
		either (float/abs f/value) = (PI / 2.0) [
			fire [TO_ERROR(math overflow)]
		][
			f/value: tan f/value
		]
		f
	]

	arcsine*: func [
		radians [integer!]
		/local
			f	[red-float!]
	][
		arc-trans radians SINE
	]

	arccosine*: func [
		radians [integer!]
		/local
			f	[red-float!]
	][
		arc-trans radians COSINE
	]

	arctangent*: func [
		radians [integer!]
		/local
			f	[red-float!]
	][
		arc-trans radians TANGENT
	]

	arctangent2*: func [
		/local
			f	[red-float!]
			n	[red-integer!]
			x	[float!]
			y	[float!]
	][
		f: as red-float! stack/arguments 
		either TYPE_OF(f) <> TYPE_FLOAT [
			n: as red-integer! f
			y: integer/to-float n/value
		][
			y: f/value
		]
		f: as red-float! stack/arguments + 1
		either TYPE_OF(f) <> TYPE_FLOAT [
			n: as red-integer! f
			x: integer/to-float n/value
			f/header: TYPE_FLOAT
		][
			x: f/value
		]
		f/value: atan2 y x
		stack/set-last as red-value! f
	]

	NaN?*: func [
		return:  [red-logic!]
		/local
			f	 [red-float!]
			ret  [red-logic!]
	][
		f: as red-float! stack/arguments
		ret: as red-logic! f
		ret/value: float/NaN? f/value
		ret/header: TYPE_LOGIC
		ret
	]

	log-2*: func [
		/local
			f	[red-float!]
	][
		f: argument-as-float
		f/value: (log f/value) / 0.6931471805599453
	]

	log-10*: func [
		/local
			f	[red-float!]
	][
		f: argument-as-float
		f/value: log10 f/value
	]

	log-e*: func [
		/local
			f	[red-float!]
	][
		f: argument-as-float
		f/value: log f/value
	]

	exp*: func [
		/local
			f	[red-float!]
	][
		f: argument-as-float
		f/value: pow 2.718281828459045235360287471 f/value
	]

	square-root*: func [
		/local
			f	[red-float!]
	][
		f: argument-as-float
		f/value: sqrt f/value
	]
	
	construct*: func [
		_with [integer!]
		only  [integer!]
		/local
			proto [red-object!]
	][
		proto: either _with >= 0 [as red-object! stack/arguments + 1][null]
		
		stack/set-last as red-value! object/construct
			as red-block! stack/arguments
			proto
			only >= 0
	]

	value?*: func [
		/local
			value  [red-value!]
			result [red-logic!]
	][
		value: stack/arguments
		if TYPE_OF(value) = TYPE_WORD [
			value: _context/get as red-word! stack/arguments
		]
		result: as red-logic! stack/arguments
		result/value: TYPE_OF(value) <> TYPE_UNSET
		result/header: TYPE_LOGIC
		result
	]
	
	try*: func [
		_all [integer!]
		return: [integer!]
		/local
			arg	   [red-value!]
			cframe [byte-ptr!]
			err	   [red-object!]
			id	   [integer!]
			result [integer!]
	][
		arg: stack/arguments
		system/thrown: 0								;@@ To be removed
		cframe: stack/get-ctop							;-- save the current call frame pointer
		result: 0
		
		either _all = -1 [
			stack/mark-try words/_try
		][
			stack/mark-try-all words/_try
		]
		catch RED_THROWN_ERROR [
			interpreter/eval as red-block! arg yes
			stack/unwind-last							;-- bypass it in case of error
		]
		either _all = -1 [
			switch system/thrown [
				RED_THROWN_BREAK
				RED_THROWN_CONTINUE
				RED_THROWN_RETURN
				RED_THROWN_EXIT [
					either stack/eval? cframe [			;-- if run from interpreter,					
						re-throw 						;-- let the exception pass through
					][
						result: system/thrown			;-- request an early exit from caller
					]
				]
				RED_THROWN_ERROR [
					err: as red-object! stack/top - 1
					assert TYPE_OF(err) = TYPE_ERROR
					id: error/get-type err
					either id = words/errors/throw/symbol [ ;-- check if error is of type THROW
						re-throw 						;-- let the error pass through
					][
						stack/adjust-post-try
					]
				]
				0		[stack/adjust-post-try]
				default [re-throw]
			]
		][												;-- TRY/ALL case, catch everything
			stack/adjust-post-try
		]
		system/thrown: 0
		result
	]

	uppercase*: func [part [integer!]][
		case-folding/change-case stack/arguments part yes
	]

	lowercase*: func [part [integer!]][
		case-folding/change-case stack/arguments part no
	]
	
	as-pair*: func [
		/local
			pair [red-pair!]
			int  [red-integer!]
	][
		pair: as red-pair! stack/arguments
		pair/header: TYPE_PAIR
		int: as red-integer! pair
		pair/x: int/value
		int: as red-integer! pair + 1
		pair/y: int/value
	]
	
	break*: func [returned [integer!]][stack/throw-break returned <> -1 no]
	
	continue*: does [stack/throw-break no yes]
	
	exit*: does [stack/throw-exit no]
	
	return*: does [stack/throw-exit yes]
	
	throw*: func [
		name [integer!]
	][
		if name = -1 [unset/push]						;-- fill this slot anyway for CATCH		
		stack/throw-throw RED_THROWN_THROW
	]
	
	catch*: func [
		name [integer!]
		/local
			arg	   [red-value!]
			c-name [red-word!]
			t-name [red-word!]
			word   [red-word!]
			tail   [red-word!]
			id	   [integer!]
			found? [logic!]
	][
		found?: no
		id:		0
		arg:	stack/arguments
		
		if name <> -1 [
			c-name: as red-word! arg + name
			id: c-name/symbol
		]
		stack/mark-catch words/_body
		catch RED_THROWN_THROW [interpreter/eval as red-block! arg yes]
		t-name: as red-word! stack/arguments + 1
		stack/unwind-last
		
		if system/thrown > 0 [
			if system/thrown <> RED_THROWN_THROW [re-throw]
			if name <> -1 [
				either TYPE_OF(t-name) = TYPE_WORD [
					either TYPE_OF(c-name) = TYPE_BLOCK [
						word: as red-word! block/rs-head as red-block! c-name
						tail: as red-word! block/rs-tail as red-block! c-name
						while [word < tail][
							if TYPE_OF(word) <> TYPE_WORD [
								fire [TO_ERROR(script invalid-refine-arg) words/_name c-name]
							]
							if EQUAL_WORDS?(t-name word) [found?: yes break]
							word: word + 1
						]
					][
						found?: EQUAL_WORDS?(t-name c-name)
					]
				][
					found?: no							;-- THROW with no /NAME refinement
				]
				unless found? [
					copy-cell as red-value! t-name stack/arguments + 1 ;-- ensure t-name is at args + 1
					stack/ctop: stack/ctop - 1			;-- skip the current CATCH call frame
					stack/throw-throw RED_THROWN_THROW
				]
			]
			system/thrown: 0
			stack/set-last stack/top - 1
			stack/top: stack/arguments + 1
		]
	]
	
	extend*: func [
		case? [integer!]
		/local
			arg [red-value!]
	][
		arg: stack/arguments
		switch TYPE_OF(arg) [
			TYPE_MAP 	[
				map/extend
					as red-hash! arg
					as red-block! arg + 1
					case? <> -1
			]
			TYPE_OBJECT [--NOT_IMPLEMENTED--]
		]
	]

	;--- Natives helper functions ---

	#enum trigonometric-type! [
		TANGENT
		COSINE
		SINE
	]

	argument-as-float: func [
		return: [red-float!]
		/local
			f	[red-float!]
			n	[red-integer!]
	][
		f: as red-float! stack/arguments
		if TYPE_OF(f) <> TYPE_FLOAT [
			f/header: TYPE_FLOAT
			n: as red-integer! f
			f/value: integer/to-float n/value
		]
		f
	]

	degree-to-radians: func [
		radians [integer!]
		type	[integer!]
		return: [red-float!]
		/local
			f	[red-float!]
			val [float!]
	][
		f: argument-as-float
		val: f/value

		if radians < 0 [
			val: val % 360.0
			if any [val > 180.0 val < -180.0] [
				val: val + either val < 0.0 [360.0][-360.0]
			]
			if any [val > 90.0 val < -90.0] [
				if type = TANGENT [
					val: val + either val < 0.0 [180.0][-180.0]
				]
				if type = SINE [
					val: (either val < 0.0 [-180.0][180.0]) - val
				]
			]
			val: val * PI / 180.0			;-- to radians
		]
		f/value: val
		f
	]

	arc-trans: func [
		radians [integer!]
		type	[integer!]
		return: [red-float!]
		/local
			f	[red-float!]
			d	[float!]
	][
		f: argument-as-float
		d: f/value

		either all [type <> TANGENT any [d < -1.0 d > 1.0]] [
			fire [TO_ERROR(math overflow)]
		][
			f/value: switch type [
				SINE	[asin d]
				COSINE	[acos d]
				TANGENT [atan d]
			]
		]

		if radians < 0 [f/value: f/value * 180.0 / PI]			;-- to degrees
		f
	]

	loop?: func [
		series  [red-series!]
		return: [logic!]	
		/local
			s	 [series!]
			type [integer!]
	][
		s: GET_BUFFER(series)
	
		type: TYPE_OF(series)
		either any [									;@@ replace with any-block?
			type = TYPE_BLOCK
			type = TYPE_PAREN
			type = TYPE_PATH
			type = TYPE_GET_PATH
			type = TYPE_SET_PATH
			type = TYPE_LIT_PATH
		][
			s/offset + series/head < s/tail
		][
			(as byte-ptr! s/offset)
				+ (series/head << (log-b GET_UNIT(s)))
				< (as byte-ptr! s/tail)
		]
	]
	
	set-obj-many: func [
		obj	  [red-object!]
		value [red-value!]
		/local
			ctx		[red-context!]
			blk		[red-block!]
			values	[red-value!]
			tail	[red-value!]
			s		[series!]
			i		[integer!]
	][
		ctx: GET_CTX(obj)
		s: as series! ctx/values/value
		values: s/offset
		tail: s/tail
		
		either TYPE_OF(value) = TYPE_BLOCK [
			blk: as red-block! value
			i: 1
			while [values < tail][
				copy-cell (_series/pick as red-series! blk i null) values
				values: values + 1
				i: i + 1
			]
		][
			while [values < tail][
				copy-cell value values
				values: values + 1
			]
		]
	]
	
	set-many: func [
		words [red-block!]
		value [red-value!]
		size  [integer!]
		/local
			v		[red-value!]
			blk		[red-block!]
			i		[integer!]
			block?	[logic!]
	][
		i: 1
		block?: TYPE_OF(value) = TYPE_BLOCK
		if block? [blk: as red-block! value]
		
		while [i <= size][
			v: either block? [_series/pick as red-series! blk i null][value]
			_context/set (as red-word! _series/pick as red-series! words i null) v
			i: i + 1
		]
	]
	
	set-many-string: func [
		words [red-block!]
		str	  [red-string!]
		size  [integer!]
		/local
			v [red-value!]
			i [integer!]
	][
		i: 1
		while [i <= size][
			_context/set (as red-word! _series/pick as red-series! words i null) _series/pick as red-series! str i null
			i: i + 1
		]
	]
	
	foreach-next-block: func [
		size	[integer!]								;-- number of words in the block
		return: [logic!]
		/local
			series [red-series!]
			blk    [red-block!]
			type   [integer!]
			result [logic!]
	][
		blk:    as red-block!  stack/arguments - 1
		series: as red-series! stack/arguments - 2

		type: TYPE_OF(series)
		assert any [									;@@ replace with any-block?/any-string? check
			type = TYPE_BLOCK
			type = TYPE_PAREN
			type = TYPE_PATH
			type = TYPE_GET_PATH
			type = TYPE_SET_PATH
			type = TYPE_LIT_PATH
			type = TYPE_STRING
			type = TYPE_FILE
			type = TYPE_URL
			type = TYPE_VECTOR
		]
		assert TYPE_OF(blk) = TYPE_BLOCK

		result: loop? series
		if result [
			either any [
				type = TYPE_STRING
				type = TYPE_FILE
				type = TYPE_URL
				type = TYPE_VECTOR
			][
				set-many-string blk as red-string! series size
			][
				set-many blk as red-value! series size
			]
		]
		series/head: series/head + size
		result
	]
	
	foreach-next: func [
		return: [logic!]
		/local
			series [red-series!]
			word   [red-word!]
			result [logic!]
	][
		word:   as red-word!   stack/arguments - 1
		series: as red-series! stack/arguments - 2

		assert any [									;@@ replace with any-block?/any-string? check
			TYPE_OF(series) = TYPE_BLOCK
			TYPE_OF(series) = TYPE_PAREN
			TYPE_OF(series) = TYPE_PATH
			TYPE_OF(series) = TYPE_GET_PATH
			TYPE_OF(series) = TYPE_SET_PATH
			TYPE_OF(series) = TYPE_LIT_PATH
			TYPE_OF(series) = TYPE_STRING
			TYPE_OF(series) = TYPE_FILE
			TYPE_OF(series) = TYPE_URL
			TYPE_OF(series) = TYPE_VECTOR
		]
		assert TYPE_OF(word) = TYPE_WORD
		
		result: loop? series
		if result [_context/set word actions/pick series 1 null]
		series/head: series/head + 1
		result
	]
	
	forall-loop: func [									;@@ inline?
		return: [logic!]
		/local
			series [red-series!]
			word   [red-word!]
	][
		word: as red-word! stack/arguments - 1
		assert TYPE_OF(word) = TYPE_WORD

		series: as red-series! _context/get word
		loop? series
	]
	
	forall-next: func [									;@@ inline?
		/local
			series [red-series!]
	][
		series: as red-series! _context/get as red-word! stack/arguments - 1
		series/head: series/head + 1
	]
	
	forall-end: func [									;@@ inline?
		/local
			series [red-series!]
			word   [red-word!]
	][
		word: 	as red-word!   stack/arguments - 1
		series: as red-series! stack/arguments - 2
		
		assert any [									;@@ replace with any-block?/any-string? check
			TYPE_OF(series) = TYPE_BLOCK
			TYPE_OF(series) = TYPE_PAREN
			TYPE_OF(series) = TYPE_PATH
			TYPE_OF(series) = TYPE_GET_PATH
			TYPE_OF(series) = TYPE_SET_PATH
			TYPE_OF(series) = TYPE_LIT_PATH
			TYPE_OF(series) = TYPE_STRING
			TYPE_OF(series) = TYPE_FILE
			TYPE_OF(series) = TYPE_URL
		]
		assert TYPE_OF(word) = TYPE_WORD

		_context/set word as red-value! series			;-- reset series to its initial offset
	]
	
	repeat-init*: func [
		cell  	[red-value!]
		return: [integer!]
		/local
			int [red-integer!]
	][
		copy-cell stack/arguments cell
		int: as red-integer! cell
		int/value										;-- overlapping /value field for integer! and char!
	]
	
	repeat-set: func [
		cell  [red-value!]
		value [integer!]
		/local
			int [red-integer!]
	][
		assert any [
			TYPE_OF(cell) = TYPE_INTEGER
			TYPE_OF(cell) = TYPE_CHAR
		]
		int: as red-integer! cell
		int/value: value								;-- overlapping /value field for integer! and char!
	]
	
	init: does [
		table: as int-ptr! allocate NATIVES_NB * size? integer!
		buffer-blk: block/make-in red/root 32			;-- block buffer for PRIN's reduce/into

		register [
			:if*
			:unless*
			:either*
			:any*
			:all*
			:while*
			:until*
			:loop*
			:repeat*
			:forever*
			:foreach*
			:forall*
			:func*
			:function*
			:does*
			:has*
			:switch*
			:case*
			:do*
			:get*
			:set*
			:print*
			:prin*
			:equal?*
			:not-equal?*
			:strict-equal?*
			:lesser?*
			:greater?*
			:lesser-or-equal?*
			:greater-or-equal?*
			:same?*
			:not*
			:halt*
			:type?*
			:reduce*
			:compose*
			:stats*
			:bind*
			:in*
			:parse*
			:union*
			:intersect*
			:unique*
			:difference*
			:exclude*
			:complement?*
			:dehex*
			:negative?*
			:positive?*
			:max*
			:min*
			:shift*
			:to-hex*
			:sine*
			:cosine*
			:tangent*
			:arcsine*
			:arccosine*
			:arctangent*
			:arctangent2*
			:NaN?*
			:log-2*
			:log-10*
			:log-e*
			:exp*
			:square-root*
			:construct*
			:value?*
			:try*
			:uppercase*
			:lowercase*
			:as-pair*
			:break*
			:continue*
			:exit*
			:return*
			:throw*
			:catch*
			:extend*
		]
	]

]
