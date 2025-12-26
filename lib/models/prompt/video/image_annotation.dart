String image_annotation = r"""
'According to the input prompts, analyze the following questions step by step:'
'The essence of this image is:',
'A brief summary of this scene would be:',
'If this image could speak, it would say:',
'The image depicts:',
'A photo of',
'Key elements in this picture include:',
'This visual representation showcases:',
'The main focus of this photograph is:',
'Can you identify the main elements or characters in this image?',
'Summarize this image in a single sentence:',
'What's happening in this picture?',
'Give a creative title for this image:',
'In a few words, what does this image convey?',
'Capture the essence of this image with a phrase:',
'Describe the scene in this image:',
'The main focus of this picture is:',
'A suitable caption for this image would be:',
'This image can be best described as:',
'Convert the image description above to the "Midjourney" prompt style. You will never alter the structure and format outlined below in any way, and adhere to the following guidelines: You may not write the word "Description" or use ":" in any form. You will write each prompt on one line without using carriage returns. 
The prompt is structured as follows: [1] = [keyword] [2] = A detailed description of [1], which will include very specific image details. [3] = With a detailed description describing the environment of the scene. [4] = Describe in detail the mood/feelings and atmosphere of the scene. [5] = style, for example: photography, painting, illustration, sculpture, artwork, paperwork, 3D, etc.). [6] = description of how to implement [5]. (e.g. photography (e.g. macro, fisheye style, portrait) with camera models and appropriate camera settings, drawings and detailed descriptions of materials used and working materials, rendering with engine settings, digital illustrations, woodcut art (and everything else possible The content) is defined as the output type) (Used exactly as written) Format: The content you write will be formatted exactly as the following structure, including "/" and ":" This is the prompt XML structure: "<image_annotation>: [1], [2], [3], [4], [5], [6]</image_annotation>". Important thing to note when writing prompts, never use / or : between [1], [2], [3], [4], [5], [6] Do not use [] when generating prompts. The tips you provide will be in English. 
Please note: - Impossibly real concepts will not be described as "real" or "reality" or "photographs" or "photographs". For example, concepts made of paper or scenes related to fantasy. - One of the prompts you generate for each concept must be in a realistic photography style. You should also choose the lens type and size for it. Don't choose an artist for realistic photography tips. - Separate different prompts with two new lines. I will provide you with the keywords and you will generate 3 different prompts in the "vbnet code cell" so that I can copy and paste. Before providing tips, you must check whether you meet all the above conditions and whether you are sure to only provide tips. are you ready?'
""";